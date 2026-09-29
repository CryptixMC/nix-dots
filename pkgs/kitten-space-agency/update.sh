#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq gnused
set -euo pipefail

# Bumps default.nix to the latest KSA Linux build. The version comes from the
# game's own update-check endpoint (AUR as fallback); the tarball from the
# community mirror, since the official download is JS-gated.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_nix="$script_dir/default.nix"

current_version=$(grep -oP '(?<=version = ")[^"]+' "$default_nix" | head -1)

latest_version=$(
  curl -sf --max-time 10 'http://ksa-master1.rocketwerkz.com:8082/version' \
    | jq -r '.Version // empty'
)

if [ -z "$latest_version" ]; then
  echo "warning: RocketWerkz master server unreachable, falling back to AUR" >&2
  latest_version=$(
    curl -sf 'https://aur.archlinux.org/rpc/v5/info?arg=kittenspaceagency-bin' \
      | jq -r '.results[0].Version' \
      | sed 's/-[^-]*$//'
  )
fi

if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
  echo "error: couldn't determine latest KSA version from any source" >&2
  exit 1
fi

if [ "$latest_version" = "$current_version" ]; then
  echo "kitten-space-agency: already at latest ($current_version)"
  exit 0
fi

build_num="${latest_version##*.}"
url="https://files.ksa-archive.net/builds/${build_num}/ksa_linux_v${latest_version}.tar.gz"

echo "kitten-space-agency: $current_version -> $latest_version"
echo "fetching $url"

hash=$(nix store prefetch-file --json "$url" | jq -r '.hash')

sed -i \
  -e "s/version = \"$current_version\";/version = \"$latest_version\";/" \
  -e "s|hash = \"sha256-[^\"]*\";|hash = \"$hash\";|" \
  "$default_nix"

echo "kitten-space-agency: updated to $latest_version ($hash)"
