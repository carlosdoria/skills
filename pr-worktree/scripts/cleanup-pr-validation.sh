#!/usr/bin/env bash
#
# cleanup-pr-validation [<feature-branch> | <caminho-do-worktree> | --all] [--force]
#
# Remove o(s) worktree(s) de validação de PR criados por
# prepare-pr-validation, sem tocar em nenhuma branch real. Sem argumento,
# remove o último worktree criado.
#
# Proteções:
#   - só remove caminhos registrados pelo prepare (ou, em registros antigos,
#     dentro de <repo>/../pr-review/); qualquer outro caminho é recusado;
#   - recusa se você estiver dentro do worktree alvo;
#   - recusa se houver edições suas além do PR (arquivos que diferem do
#     commit do PR); --force remove mesmo assim, perdendo essas edições;
#   - nunca usa `rm -rf`: se o Git não conseguir remover, o script aborta.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-pr-validation.sh"

REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
STATE_DIR="$GIT_COMMON_DIR/pr-validation"
ACTIVE_FILE="$STATE_DIR/active-worktrees"
LAST_FILE="$STATE_DIR/last-worktree"

FORCE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

MAIN_ROOT="$(abs_dir "$(dirname "$GIT_COMMON_DIR")")"
ALLOWED_ROOT="$(dirname "$REPO_ROOT")/pr-review"
SKIPPED=0

# Valida o caminho e devolve 0 se puder ser removido. Mensagens em stderr.
pode_remover() {
  local path="$1" real head changes
  real="$(abs_dir "$path")" || { echo "Caminho inacessível: $path" >&2; return 1; }

  if [[ "$real" == "$MAIN_ROOT" ]]; then
    echo "Recusado: '$real' é o repositório principal." >&2; return 1
  fi
  if ! is_registered "$path" "$ACTIVE_FILE" && [[ "$real" != "$(abs_dir "$ALLOWED_ROOT" 2>/dev/null || echo /nonexistent)"/pr-* ]]; then
    echo "Recusado: '$real' não é um worktree de validação registrado." >&2; return 1
  fi
  if ! git worktree list --porcelain | grep -qxF "worktree $real" \
     && ! git worktree list --porcelain | grep -qxF "worktree $path"; then
    echo "Recusado: '$real' não é um worktree conhecido pelo Git." >&2; return 1
  fi
  case "$(pwd -P)/" in
    "$real"/*) echo "Recusado: você está dentro de '$real'. Rode a partir do repositório principal." >&2; return 1 ;;
  esac

  [[ "$FORCE" -eq 1 ]] && return 0

  head="$(registered_head "$path" "$ACTIVE_FILE")"
  if [[ -z "$head" ]]; then
    echo "Não dá para verificar edições em '$real' (registro antigo, sem commit do PR)." >&2
    echo "Confira o conteúdo e use --force se puder descartá-lo." >&2
    return 1
  fi
  changes="$(local_changes "$path" "$head")"
  if [[ -n "$changes" ]]; then
    echo "O worktree '$real' tem edições suas além do PR:" >&2
    echo "$changes" | sed 's/^/  /' >&2
    echo "Use --force para remover mesmo assim (essas edições serão perdidas)." >&2
    return 1
  fi
  return 0
}

remove_one() {
  local path="$1"
  if [[ -d "$path" ]]; then
    if ! pode_remover "$path"; then
      SKIPPED=$((SKIPPED + 1))
      return 0
    fi
    echo "==> Removendo worktree: $path"
    # --force é necessário porque o reset deixa o worktree "sujo" por
    # desenho; a verificação de edições acima é a proteção real.
    git worktree remove --force "$path" || {
      echo "O Git não conseguiu remover '$path'. Nada foi apagado à mão; verifique e tente de novo." >&2
      SKIPPED=$((SKIPPED + 1)); return 0
    }
  else
    echo "==> Pasta '$path' não existe mais; apenas limpando registro."
  fi
  if [[ -f "$ACTIVE_FILE" ]]; then
    awk -F'|' -v p="$path" '$3 != p' "$ACTIVE_FILE" > "${ACTIVE_FILE}.tmp" || true
    mv -f "${ACTIVE_FILE}.tmp" "$ACTIVE_FILE"
  fi
  [[ -f "$LAST_FILE" ]] && grep -qxF "$path" "$LAST_FILE" 2>/dev/null && rm -f "$LAST_FILE"
  return 0
}

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
if [[ "$SKIPPED" -gt 0 ]]; then
  exit 1
fi
echo "==> Limpeza concluída."
