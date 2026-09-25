#!/usr/bin/env bash
# Moves source.json to the head of its pinned branch. Run from the repo root via
# `nix run .#update`, which supplies git/jq/curl/nix on PATH.
#
# Deliberately never switches branch: Terasic publishes one branch per board
# revision + kernel base, and a new base needs its config re-validated on
# hardware. New candidate branches are only reported, on stderr as
# `NEW-BRANCH <name>` lines that the update workflow copies into its PR body.
set -euo pipefail

src=${1:?usage: update.sh path/to/source.json}
owner=$(jq -r .owner "$src")
repo=$(jq -r .repo "$src")
branch=$(jq -r .branch "$src")
old_rev=$(jq -r .rev "$src")
url="https://github.com/$owner/$repo"

# Branch naming is <board>-<kernel>-lts, e.g. de25-nano-6.12.11-lts.
board_prefix=${branch%-*-lts}
git ls-remote --heads "$url" "$board_prefix-*" |
  awk '{sub("refs/heads/", "", $2); print $2}' |
  grep -vxF "$branch" |
  sed 's/^/NEW-BRANCH /' >&2 || true

new_rev=$(git ls-remote --heads "$url" "refs/heads/$branch" | cut -f1)
if [ -z "$new_rev" ]; then
  echo "error: branch $branch no longer exists on $url" >&2
  exit 1
fi
if [ "$new_rev" = "$old_rev" ]; then
  echo "$owner/$repo@$branch: up to date at $old_rev" >&2
  exit 0
fi

hash=$(nix flake prefetch --json "github:$owner/$repo/$new_rev" | jq -r .hash)

makefile=$(curl -fsSL "https://raw.githubusercontent.com/$owner/$repo/$new_rev/Makefile")
field() { sed -n "s/^$1 *= *//p" <<<"$makefile" | head -n1; }
version="$(field VERSION).$(field PATCHLEVEL).$(field SUBLEVEL)$(field EXTRAVERSION)"

jq --arg rev "$new_rev" --arg hash "$hash" --arg version "$version" \
  '.rev = $rev | .hash = $hash | .version = $version' "$src" > "$src.tmp"
mv "$src.tmp" "$src"
echo "$owner/$repo@$branch: $old_rev -> $new_rev ($version)" >&2
