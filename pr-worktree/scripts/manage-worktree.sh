#!/usr/bin/env bash
#
# manage-worktree <subcomando> [args]
#
#   new <nova-branch> [--from <base>] [--dir <caminho>]
#       Cria uma worktree nova, com branch nova, a partir de uma base
#       (outra worktree ou uma branch). A base é atualizada por
#       fast-forward antes, para que a branch nova não nasça atrasada.
#
#   list
#       Lista as worktrees do repositório, separando as de
#       desenvolvimento das descartáveis de validação de PR.
#
#   update [<alvo>]
#       Atualiza a worktree por fast-forward com o remoto. Se a branch
#       divergiu, recusa e explica — nunca rebaseia nem força.
#
#   remove <alvo> [--force]
#       Remove a worktree e, se a branch dela já foi mesclada, oferece
#       apagar a branch também. Recusa se houver trabalho não salvo.
#
# <alvo> pode ser o caminho da worktree ou o nome da branch.
# Worktrees ficam em uma pasta irmã à raiz do repositório principal.
#
set -euo pipefail

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
SUBCMD="$1"; shift

GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
PR_STATE_FILE="$GIT_COMMON_DIR/pr-validation/active-worktrees"

# Raiz "canônica" do projeto: o primeiro worktree da lista do Git.
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
SIBLING_ROOT="$(dirname "$MAIN_ROOT")"

# Uma worktree é de validação de PR se estiver registrada pelo prepare.
eh_worktree_de_pr() {
  local p="$1"
  [[ -f "$PR_STATE_FILE" ]] || return 1
  awk -F'|' -v p="$p" '$3 == p { encontrado=1 } END { exit !encontrado }' "$PR_STATE_FILE"
}

# Resolve um alvo (caminho ou nome de branch) para o caminho da worktree.
resolver_worktree() {
  local alvo="$1" path branch
  if [[ -d "$alvo" ]]; then
    git -C "$alvo" rev-parse --show-toplevel 2>/dev/null && return 0
    return 1
  fi
  while IFS= read -r linha; do
    case "$linha" in
      worktree\ *) path="${linha#worktree }" ;;
      branch\ *)
        branch="${linha#branch refs/heads/}"
        if [[ "$branch" == "$alvo" ]]; then printf '%s' "$path"; return 0; fi
        ;;
    esac
  done < <(git worktree list --porcelain)
  return 1
}

branch_da_worktree() {
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached)"
}

esta_suja() {
  [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

case "$SUBCMD" in

  new)
    [[ $# -ge 1 ]] || usage
    NOVA_BRANCH="$1"; shift
    BASE=""
    DIR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --from) BASE="${2:?--from precisa de um valor}"; shift 2 ;;
        --dir)  DIR="${2:?--dir precisa de um valor}"; shift 2 ;;
        *) echo "Opção desconhecida: $1" >&2; usage ;;
      esac
    done

    if git show-ref --verify --quiet "refs/heads/${NOVA_BRANCH}"; then
      echo "A branch '$NOVA_BRANCH' já existe. Escolha outro nome ou remova a existente." >&2
      exit 1
    fi

    # Base padrão: a branch padrão do remoto; se não houver, a branch atual.
    if [[ -z "$BASE" ]]; then
      BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
      [[ -n "$BASE" ]] || BASE="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      [[ -n "$BASE" ]] || { echo "Não consegui detectar a base. Use --from <worktree|branch>." >&2; exit 1; }
      echo "==> Base não informada; usando: $BASE"
    fi

    # A base pode ser o caminho de outra worktree ou um nome de branch.
    BASE_DIR=""
    if [[ -d "$BASE" ]]; then
      BASE_DIR="$(git -C "$BASE" rev-parse --show-toplevel)"
      BASE_BRANCH="$(branch_da_worktree "$BASE_DIR")"
      [[ "$BASE_BRANCH" != "(detached)" ]] || {
        echo "A worktree base '$BASE' está em HEAD detached; não dá para partir dela." >&2; exit 1; }
    else
      BASE_BRANCH="$BASE"
      BASE_DIR="$(resolver_worktree "$BASE_BRANCH" || true)"
    fi

    echo "==> Atualizando a base '$BASE_BRANCH' (fast-forward)..."
    git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
    if [[ -n "$BASE_DIR" ]] && ! esta_suja "$BASE_DIR"; then
      git -C "$BASE_DIR" merge --ff-only "origin/${BASE_BRANCH}" --quiet 2>/dev/null \
        || echo "    (não foi possível fast-forward; seguindo com o estado atual da base)"
    elif [[ -n "$BASE_DIR" ]]; then
      echo "    (worktree da base tem alterações não salvas; não vou tocá-la)"
    fi

    # Ponto de partida: prefere o remoto atualizado, cai para o local.
    PONTO="$(git rev-parse --verify --quiet "origin/${BASE_BRANCH}^{commit}" || true)"
    [[ -n "$PONTO" ]] || PONTO="$(git rev-parse --verify --quiet "${BASE_BRANCH}^{commit}" || true)"
    [[ -n "$PONTO" ]] || { echo "Base '$BASE_BRANCH' não encontrada." >&2; exit 1; }

    SLUG="$(printf '%s' "$NOVA_BRANCH" | tr '/' '-' | tr -c 'a-zA-Z0-9._-' '-')"
    WORKTREE_PATH="${DIR:-${SIBLING_ROOT}/${SLUG}}"

    [[ ! -e "$WORKTREE_PATH" ]] || { echo "Já existe algo em '$WORKTREE_PATH'. Abortando." >&2; exit 1; }

    echo "==> Criando worktree '$NOVA_BRANCH' a partir de '$BASE_BRANCH'..."
    git worktree add -b "$NOVA_BRANCH" "$WORKTREE_PATH" "$PONTO"

    echo
    echo "==> Pronto."
    echo "    Branch:   $NOVA_BRANCH"
    echo "    Base:     $BASE_BRANCH ($(git rev-parse --short "$PONTO"))"
    echo "    Worktree: $WORKTREE_PATH"
    echo
    echo "    Para entrar (abra no editor de sua preferência):"
    echo "      cd \"$WORKTREE_PATH\""
    ;;

  list)
    echo "=== WORKTREES DE DESENVOLVIMENTO ==="
    encontrou_dev=0
    echo "=== VALIDAÇÃO DE PR (descartáveis) ==="  >/dev/null  # ordem tratada abaixo
    DEV_OUT=""; PR_OUT=""
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      branch="$(branch_da_worktree "$path")"
      sujo=""; esta_suja "$path" && sujo="  [alterações não salvas]"
      linha="  ${branch}	${path}${sujo}"
      if eh_worktree_de_pr "$path"; then
        PR_OUT+="$linha"$'\n'
      else
        DEV_OUT+="$linha"$'\n'
        encontrou_dev=1
      fi
    done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')

    printf '%s' "${DEV_OUT:-  (nenhuma)
}"
    echo
    echo "=== VALIDAÇÃO DE PR (descartáveis) ==="
    printf '%s' "${PR_OUT:-  (nenhuma)
}"
    [[ "$encontrou_dev" -eq 1 ]] || true
    ;;

  update)
    ALVO="${1:-$(git rev-parse --show-toplevel)}"
    WT="$(resolver_worktree "$ALVO" || true)"
    [[ -n "$WT" ]] || { echo "Worktree não encontrada para '$ALVO'." >&2; git worktree list >&2; exit 1; }

    if eh_worktree_de_pr "$WT"; then
      echo "'$WT' é uma worktree de validação de PR (HEAD detached)." >&2
      echo "Não se atualiza esse tipo: recrie com prepare-pr-validation." >&2
      exit 1
    fi

    BR="$(branch_da_worktree "$WT")"
    [[ "$BR" != "(detached)" ]] || { echo "Worktree em HEAD detached; nada a atualizar." >&2; exit 1; }

    if esta_suja "$WT"; then
      echo "A worktree tem alterações não salvas. Faça commit ou stash antes de atualizar." >&2
      exit 1
    fi

    echo "==> Buscando '$BR' no remoto..."
    git -C "$WT" fetch origin "$BR" --quiet 2>/dev/null || {
      echo "A branch '$BR' não existe no remoto; nada a atualizar."; exit 0; }

    LOCAL="$(git -C "$WT" rev-parse HEAD)"
    REMOTO="$(git -C "$WT" rev-parse "origin/${BR}")"
    BASE_COMUM="$(git -C "$WT" merge-base HEAD "origin/${BR}")"

    if [[ "$LOCAL" == "$REMOTO" ]]; then
      echo "==> Já atualizada."
    elif [[ "$BASE_COMUM" == "$LOCAL" ]]; then
      git -C "$WT" merge --ff-only "origin/${BR}"
      echo "==> Atualizada por fast-forward."
    elif [[ "$BASE_COMUM" == "$REMOTO" ]]; then
      echo "==> Sua branch está à frente do remoto. Nada a trazer (falta um push)."
    else
      echo "As duas pontas divergiram: há commits locais e remotos diferentes." >&2
      echo "Não vou rebasear nem forçar merge por conta própria — resolva você:" >&2
      echo "  git -C \"$WT\" rebase origin/${BR}   # ou merge, conforme o fluxo do time" >&2
      exit 1
    fi
    ;;

  remove)
    [[ $# -ge 1 ]] || usage
    ALVO="$1"; shift
    FORCE=0
    [[ "${1:-}" == "--force" ]] && FORCE=1

    WT="$(resolver_worktree "$ALVO" || true)"
    [[ -n "$WT" ]] || { echo "Worktree não encontrada para '$ALVO'." >&2; git worktree list >&2; exit 1; }

    ATUAL="$(git rev-parse --show-toplevel)"
    [[ "$WT" != "$ATUAL" ]] || {
      echo "Você está dentro de '$WT'. Saia dela antes de removê-la." >&2; exit 1; }
    [[ "$WT" != "$MAIN_ROOT" ]] || {
      echo "'$WT' é a worktree principal do repositório; não pode ser removida." >&2; exit 1; }

    BR="$(branch_da_worktree "$WT")"

    if esta_suja "$WT" && [[ "$FORCE" -eq 0 ]]; then
      echo "A worktree '$WT' tem alterações não salvas:" >&2
      git -C "$WT" status --short >&2
      echo "Use --force para remover mesmo assim (o trabalho será perdido)." >&2
      exit 1
    fi

    echo "==> Removendo worktree: $WT"
    git worktree remove ${FORCE:+--force} "$WT"
    git worktree prune

    if [[ "$BR" != "(detached)" ]] && git show-ref --verify --quiet "refs/heads/${BR}"; then
      if git branch --merged 2>/dev/null | sed 's/^[ *]*//' | grep -qx "$BR"; then
        echo "==> A branch '$BR' já foi mesclada e continua existindo."
        echo "    Para apagá-la também: git branch -d \"$BR\""
      else
        echo "==> A branch '$BR' foi preservada (tem commits não mesclados)."
      fi
    fi
    echo "==> Limpeza concluída."
    ;;

  *)
    echo "Subcomando desconhecido: $SUBCMD" >&2
    usage
    ;;
esac
