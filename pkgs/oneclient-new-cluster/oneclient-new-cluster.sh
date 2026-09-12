#!/usr/bin/env bash
#
# OneClient (Polyfrost) has no UI for creating a blank cluster: every cluster
# in the app is auto-provisioned from Polyfrost's own bundle/version catalog
# (see oneclient_core::clusters::provision::{ensure_from_bundles,ensure_from_versions}
# in github.com/Polyfrost/OneLauncher). The only in-app path that even mentions
# creating one is the drag-and-drop dialog, which just tells you to "create a
# cluster first" with no way to do so.
#
# This replicates oneclient_cluster::manager::ClusterManager::create_core:
# sanitize the name, pick a free folder under clusters/, create the standard
# content dirs, and insert matching rows into setting_profiles + clusters.

set -euo pipefail

DATA_DIR="${ONECLIENT_DATA_DIR:-$HOME/.local/share/oneclient}"
DB="$DATA_DIR/user_data.db"
CLUSTERS_DIR="$DATA_DIR/clusters"

usage() {
  cat <<EOF
Usage: oneclient-new-cluster <name> <mc_version> <loader> [loader_version]

  <name>           Display name, e.g. "My Modpack"
  <mc_version>     e.g. 1.20.1
  <loader>         one of: vanilla forge neoforge quilt fabric legacyfabric
  [loader_version] e.g. 47.4.0 (required for anything but vanilla)

Creates the cluster's folder (with mods/, resourcepacks/, shaderpacks/,
datapacks/, worlds/) under:
  $CLUSTERS_DIR

and registers it in OneClient's database so it shows up next time you
launch the app. Drop your mods/config/resourcepacks into the printed
folder before (or after) first launch.
EOF
}

if [ "$#" -lt 3 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 1
fi

raw_name="$1"
mc_version="$2"
loader_input="$3"
loader_version="${4:-}"

if [ ! -f "$DB" ]; then
  echo "error: OneClient database not found at $DB (has OneClient been run at least once?)" >&2
  exit 1
fi

if pgrep -x oneclient >/dev/null 2>&1; then
  echo "warning: OneClient looks like it's running. This should still be safe (SQLite WAL)," >&2
  echo "         but restart the app afterward if the new cluster doesn't show up." >&2
fi

case "$(printf '%s' "$loader_input" | tr '[:upper:]' '[:lower:]')" in
  vanilla|minecraft) mc_loader=0 ;;
  forge) mc_loader=1 ;;
  neoforge) mc_loader=2 ;;
  quilt) mc_loader=3 ;;
  fabric) mc_loader=4 ;;
  legacyfabric|legacy-fabric) mc_loader=5 ;;
  *)
    echo "error: unknown loader '$loader_input' (want: vanilla forge neoforge quilt fabric legacyfabric)" >&2
    exit 1
    ;;
esac

# Mirrors ClusterManager::sanitize_name: keep ascii alnum plus _-. () and space, then trim.
name="$(printf '%s' "$raw_name" | tr -cd 'A-Za-z0-9_.() -')"
name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [ -z "$name" ]; then
  echo "error: name is empty after sanitizing (allowed: letters, digits, spaces, _ - . ( ))" >&2
  exit 1
fi

mkdir -p "$CLUSTERS_DIR"

# Mirrors resolve_unique_folder_name: append " (1)", " (2)", ... until free.
folder_name="$name"
if [ -e "$CLUSTERS_DIR/$folder_name" ]; then
  n=1
  while [ -e "$CLUSTERS_DIR/$name ($n)" ]; do
    n=$((n + 1))
  done
  folder_name="$name ($n)"
fi

cluster_path="$CLUSTERS_DIR/$folder_name"
mkdir -p "$cluster_path"/{mods,resourcepacks,shaderpacks,datapacks,worlds}

created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

name_sql="$(sql_escape "$name")"
folder_sql="$(sql_escape "$folder_name")"
version_sql="$(sql_escape "$mc_version")"

if [ -n "$loader_version" ]; then
  loader_version_sql="'$(sql_escape "$loader_version")'"
else
  loader_version_sql="NULL"
fi

sqlite3 "$DB" <<SQL
BEGIN;
INSERT INTO setting_profiles (name) VALUES ('$name_sql') ON CONFLICT(name) DO NOTHING;
INSERT INTO clusters (
  name, folder_name, mc_version, mc_loader, mc_loader_version,
  setting_profile_name, stage, created_at
) VALUES (
  '$name_sql', '$folder_sql', '$version_sql', $mc_loader, $loader_version_sql,
  '$name_sql', 0, '$created_at'
);
COMMIT;
SQL

echo "Created cluster '$name' ($mc_version, loader=$loader_input${loader_version:+ $loader_version})"
echo "Folder: $cluster_path"
echo "Drop mods into: $cluster_path/mods"
echo "(Re)start OneClient to see it."
