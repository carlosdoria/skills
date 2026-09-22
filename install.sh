#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

echo "🚀 Instalando Claude Code Skills..."

mkdir -p "$SKILLS_DIR"

for skill_dir in "$REPO_DIR"/*; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue

  skill_name="$(basename "$skill_dir")"

  rm -rf "$SKILLS_DIR/$skill_name"
  cp -R "$skill_dir" "$SKILLS_DIR/$skill_name"

  echo "✅ $skill_name"
done

echo ""
echo "Skills instaladas em:"
echo "$SKILLS_DIR"
echo ""
echo "Abra uma nova sessão do Claude Code para carregá-las."
