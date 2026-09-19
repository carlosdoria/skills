#!/usr/bin/env bash
#
# cleanup-pr-validation [<feature-branch> | <caminho-do-worktree> | --all]
#
# Remove o(s) worktree(s) de validação de PR criados por
# prepare-pr-validation, sem tocar em nenhuma branch real. Sem argumento,
# remove o último worktree criado.
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
STATE_DIR="$GIT_COMMON_DIR/pr-validation"
ACTIVE_FILE="$STATE_DIR/active-worktrees"
LAST_FILE="$STATE_DIR/last-worktree"

remove_one() {
  local path="$1"
  if [[ -d "$path" ]]; then
    echo "==> Removendo worktree: $path"
    git worktree remove --force "$path" 2>/dev/null || rm -rf "$path"
  else
    echo "==> Pasta '$path' não existe mais; apenas limpando registro."
  fi
  if [[ -f "$ACTIVE_FILE" ]]; then
    grep -vF "|${path}" "$ACTIVE_FILE" > "${ACTIVE_FILE}.tmp" 2>/dev/null || true
    mv -f "${ACTIVE_FILE}.tmp" "$ACTIVE_FILE"
  fi
  [[ -f "$LAST_FILE" ]] && grep -qxF "$path" "$LAST_FILE" 2>/dev/null && rm -f "$LAST_FILE"
}

if [[ "${1:-}" == "--all" ]]; then
  if [[ -f "$ACTIVE_FILE" ]]; then
    while IFS='|' read -r _branch _base wt_path _mergebase; do
      [[ -n "$wt_path" ]] && remove_one "$wt_path"
    done < "$ACTIVE_FILE"
  fi
  git worktree prune
  echo "==> Todos os worktrees de validação foram removidos."
  exit 0
fi

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  [[ -f "$LAST_FILE" ]] || { echo "Nenhum worktree de validação registrado. Informe a branch ou o caminho." >&2; exit 1; }
  TARGET="$(cat "$LAST_FILE")"
fi

# Se não for um caminho existente, tenta resolver por nome de branch no registro
if [[ ! -d "$TARGET" ]] && [[ -f "$ACTIVE_FILE" ]]; then
  MATCH="$(awk -F'|' -v t="$TARGET" '$1 == t { print $3 }' "$ACTIVE_FILE" | tail -n1)"
  [[ -n "$MATCH" ]] && TARGET="$MATCH"
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Não encontrei um worktree de validação para '$TARGET'." >&2
  echo "Worktrees ativos:" >&2
  git worktree list >&2
  exit 1
fi

remove_one "$TARGET"
git worktree prune
echo "==> Limpeza concluída."
