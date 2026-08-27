#!/usr/bin/env bash

set -e

# Installs this skill into the Copilot skills directory as `local-code-review`.

SKILL_NAME="local-code-review"
TARGET_DIR="$HOME/.copilot/skills/$SKILL_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Installing '$SKILL_NAME' into: $TARGET_DIR"

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

cp "$SCRIPT_DIR/SKILL.md" "$TARGET_DIR/"
cp -r "$SCRIPT_DIR/assets" "$TARGET_DIR/"
cp -r "$SCRIPT_DIR/references" "$TARGET_DIR/"
cp -r "$SCRIPT_DIR/scripts" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/scripts/collect-review-context.sh"

echo "✅ Done. Invoke it in Copilot Chat or Copilot CLI with:"
echo "   /$SKILL_NAME"
