{ pkgs, ... }:

let
  # Reports 5-hour and 7-day subscription usage from the undocumented
  # /api/oauth/usage endpoint using Claude Code's OAuth token. No refresh:
  # an expired token is reported until `claude` is run again.
  # The endpoint rate-limits hard (429s with ~20 min retry-after); poll rarely.
  claudeUsageCheck = pkgs.writeShellScriptBin "claude-usage-check" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.curl
        pkgs.jq
      ]
    }:$PATH

    creds="$HOME/.claude/.credentials.json"
    if [ ! -f "$creds" ]; then
      echo '{"ok":false,"error":"no credentials file"}'
      exit 0
    fi

    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null || echo "")
    if [ -z "$token" ]; then
      echo '{"ok":false,"error":"no access token"}'
      exit 0
    fi

    body_file=$(mktemp)
    headers_file=$(mktemp)
    trap 'rm -f "$body_file" "$headers_file"' EXIT

    http_code=$(curl -sS --max-time 10 -o "$body_file" -D "$headers_file" -w '%{http_code}' \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" || echo "000")

    body=$(cat "$body_file" 2>/dev/null || echo "")
    # `|| true`: grep exits 1 without a retry-after header, which set -e would abort on.
    retry_after=$(grep -i '^retry-after:' "$headers_file" 2>/dev/null | tr -d '\r' | awk '{print $2}' || true)

    if [ "$http_code" != "200" ]; then
      case "$http_code" in
        401) msg="token expired -- run claude to refresh" ;;
        403) msg="token missing profile scope -- run claude login" ;;
        429)
          # Real if/else: an `&&` form would trip set -e when retry_after is empty.
          if [ -n "$retry_after" ]; then
            msg="rate limited by anthropic (retry in ''${retry_after}s)"
          else
            msg="rate limited by anthropic"
          fi
          ;;
        000) msg="network error" ;;
        *) msg="http $http_code" ;;
      esac
      jq -nc --arg msg "$msg" '{ok:false,error:$msg}'
      exit 0
    fi

    echo "$body" | jq -c '{
      ok: true,
      fiveHourPct: (.five_hour.utilization // 0),
      fiveHourResetsAt: (.five_hour.resets_at // ""),
      sevenDayPct: (.seven_day.utilization // 0),
      sevenDayResetsAt: (.seven_day.resets_at // "")
    }' 2>/dev/null || echo '{"ok":false,"error":"bad response body"}'
  '';
in
{
  home.packages = [ claudeUsageCheck ];
}
