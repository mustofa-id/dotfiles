#!/usr/bin/env bash
set -euo pipefail

# Dotfiles installer
# - dry-run by default
# - --apply to actually create symlinks

ROOT="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=true

# Parse flags
if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN=false
fi

# Helper to run commands safely
run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# -------------------------------
# Link top-level items from src to dst
# -------------------------------
link_top_level() {
  local src="$1"
  local dst="$2"

  [ -d "$src" ] || return 0  # Skip if source doesn't exist
  mkdir -p "$dst"

  # Include hidden files, but skip "." and ".."
  shopt -s dotglob nullglob

  for item in "$src"/* "$src"/.[!.]*; do
    [ -e "$item" ] || continue  # skip if no matches
    name="$(basename "$item")"
    target="$dst/$name"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "⚠️  Skipping $target (exists and not a symlink)"
      continue
    fi

    mkdir -p "$(dirname "$target")"
    run ln -sfn "$item" "$target"
  done

  shopt -u dotglob nullglob
}

# -------------------------------
# Main
# -------------------------------
echo "=============================="
if $DRY_RUN; then
  echo "Dry-run mode (no changes will be made)"
  echo "Use './install.sh --apply' to create symlinks"
else
  echo "Applying changes..."
fi
echo "=============================="

# Map source directories to their destinations
declare -A MAP=(
  ["$ROOT/config"]="$HOME/.config"
  ["$ROOT/home"]="$HOME"
)

for src in "${!MAP[@]}"; do
  link_top_level "$src" "${MAP[$src]}"
done

echo "=============================="
echo "Done."
