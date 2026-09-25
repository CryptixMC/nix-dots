{ pkgs, ... }:

let
  # Reads Claude Code's own OAuth credentials (~/.claude/.credentials.json,
  # written by `claude login`/normal CLI use) and hits Anthropic's
  # undocumented /api/oauth/usage endpoint for this account's rolling 5-hour
  # and 7-day (weekly) subscription usage -- the same numbers claude.ai's
  # own usage meter shows. No token refresh is attempted here: if the access
  # token has expired, this just reports the failure and waits for the user
  # to run `claude` normally again (which refreshes it as a side effect).
  #
  # Confirmed live: this endpoint rate-limits aggressively (a handful of
  # manual test calls in one session was enough to get a 429 with an
  # 1100+s retry-after). The caller (QubiStatus.qml) must poll this
  # infrequently -- see its own comment for the interval this earned.
  claudeUsageCheck = pkgs.writeShellScriptBin "claude-usage-check" ''
    set -euo pipefail
    export PATH=${pkgs.lib.makeBinPath [ pkgs.curl pkgs.jq ]}:$PATH

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
    # grep exits 1 when there's no retry-after header (true for every
    # non-429 response) -- under `set -e`/pipefail that would otherwise
    # kill the script right here before any output is ever produced.
    retry_after=$(grep -i '^retry-after:' "$headers_file" 2>/dev/null | tr -d '\r' | awk '{print $2}' || true)

    if [ "$http_code" != "200" ]; then
      case "$http_code" in
        401) msg="token expired -- run claude to refresh" ;;
        403) msg="token missing profile scope -- run claude login" ;;
        429)
          # A plain `&&`-in-substitution here would trip `set -e` when
          # retry_after is empty (the `[ -n ]` test fails, `&&` short-
          # circuits, substitution "fails") -- same footgun as the grep
          # above, so this stays a real if/else instead.
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
