#!/usr/bin/env bash
# Export Godot Web build and publish to the gh-pages branch.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUT=$(mktemp -d)
WT=$(mktemp -d)
trap 'git worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$OUT" "$WT"' EXIT

godot --headless --export-release "Web" "$OUT/index.html"

git fetch origin gh-pages
git worktree add "$WT" gh-pages
find "$WT" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -r "$OUT"/. "$WT/"
touch "$WT/.nojekyll"

git -C "$WT" add -A
if git -C "$WT" diff --cached --quiet; then
    echo "No changes to publish."
    exit 0
fi
git -C "$WT" commit -m "Publish Godot Web export"
git -C "$WT" push origin gh-pages
