#!/usr/bin/env bash
set -euo pipefail

# Dotfiles installer
# - dry-run by default
# - --apply to actually create symlinks

ROOT="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=true
EXCLUDE_FILE="$ROOT/.exclude"
declare -A EXCLUDES=()

# -------------------------------
# Load exclude list
# -------------------------------
if [[ -f "$EXCLUDE_FILE" ]]; then
  while IFS= read -r line; do
    # Trim whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip comments and empty lines
    [[ -z "$line" || "$line" == \#* ]] && continue

    EXCLUDES["$line"]=1
  done < "$EXCLUDE_FILE"
fi

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

  [ -d "$src" ] || return 0
  mkdir -p "$dst"

  shopt -s dotglob nullglob

  for item in "$src"/* "$src"/.[!.]*; do
    [ -e "$item" ] || continue

    name="$(basename "$item")"
    target="$dst/$name"

    # -------------------------------
    # Handle excludes
    # -------------------------------
    if [[ -n "${EXCLUDES[$name]:-}" ]]; then
      if [[ -L "$target" ]]; then
        echo "🧹 Removing excluded symlink $target"
        run rm "$target"
      else
        echo "⏭️  Skipping excluded $name"
      fi
      continue
    fi

    # we do replace symlink in case if it broken link
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

declare -A MAP=(
  ["$ROOT/config"]="$HOME/.config"
  ["$ROOT/home"]="$HOME"
)

for src in "${!MAP[@]}"; do
  link_top_level "$src" "${MAP[$src]}"
done

echo "=============================="
echo "Done."
