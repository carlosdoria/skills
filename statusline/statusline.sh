#!/usr/bin/env bash
# Statusline do Claude Code: pasta (branch) · modelo · contexto usado · custo.
#
# O Claude Code manda o estado da sessão em JSON no stdin e mostra a primeira
# linha do stdout. Roda localmente e não gasta tokens. Configure em
# ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "bash ~/repos/labs/skills/main/statusline/statusline.sh"}

set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "statusline: instale o jq"
  exit 0
fi

entrada=$(cat)

campo() { printf '%s' "$entrada" | jq -r "$1 // empty" 2>/dev/null; }

dir=$(campo '.workspace.current_dir')
[ -n "$dir" ] || dir=$(campo '.cwd')
modelo=$(campo '.model.display_name')
contexto=$(campo '.context_window.used_percentage')
custo=$(campo '.cost.total_cost_usd')

partes=()

if [ -n "$dir" ]; then
  local_=$(basename "$dir")
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null || true)
  if [ -n "$branch" ]; then
    partes+=("$local_ ($branch)")
  else
    partes+=("$local_")
  fi
fi

[ -n "$modelo" ] && partes+=("$modelo")
# Formata com awk em LC_ALL=C: o printf do bash rejeita o ponto decimal
# quando o locale é pt_BR, e o prefixo LC_ALL=C não vale para builtins.
fmt() { LC_ALL=C awk -v v="$2" -v f="$1" 'BEGIN { printf f, v }'; }
[ -n "$contexto" ] && partes+=("ctx $(fmt '%.0f' "$contexto")%")
[ -n "$custo" ] && partes+=("\$$(fmt '%.2f' "$custo")")

[ ${#partes[@]} -gt 0 ] || exit 0

saida=""
for p in "${partes[@]}"; do
  if [ -z "$saida" ]; then saida="$p"; else saida="$saida · $p"; fi
done
printf '%s\n' "$saida"
