#!/usr/bin/env bash
#
# manage-worktree <subcomando> [args]
#
#   clone <url> [--dir <destino>] [--branch <nome>]
#       Clona um repositório remoto direto no formato bare + worktree por
#       branch: <destino>/.bare (bare) e <destino>/<branch-padrão> (a
#       primeira worktree, com a branch padrão do remoto já dentro dela).
#       Nenhuma branch fica com checkout na raiz do projeto — esse é o
#       padrão para todo repositório novo gerenciado por esta skill.
#
#   bootstrap-bare [<caminho>] [--confirmo-riscos]
#       Converte um repositório normal (não-bare) já existente, com a
#       working tree na raiz, para o mesmo formato bare + worktree por
#       branch. Recusa se a árvore não estiver limpa (tracked ou
#       untracked). A branch atualmente com checkout na raiz (padrão:
#       repositório do diretório atual) vira uma worktree irmã.
#       Apaga também qualquer arquivo ignorado pelo .gitignore que estiver
#       solto na raiz (a checagem de árvore limpa não cobre esses
#       arquivos). Por isso só roda com --confirmo-riscos: sem a flag,
#       imprime o aviso e sai sem mexer em nada. Mostre o aviso ao usuário
#       e só use a flag depois que ele confirmar de forma explícita.
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
# Worktrees ficam em uma pasta irmã à raiz do repositório principal — que,
# no padrão bare (clone/bootstrap-bare), é a própria pasta do projeto, já
# que ela não tem mais working tree própria.
#
set -euo pipefail

usage() {
  sed -n '3,44p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
SUBCMD="$1"; shift

# clone e bootstrap-bare ainda não têm um repositório Git para inspecionar
# neste ponto (clone) ou operam sobre um caminho arbitrário (bootstrap-bare
# recebe o caminho como argumento), então saem antes do bloco que assume um
# repositório já resolvido no diretório atual.
case "$SUBCMD" in
  clone|bootstrap-bare) : ;;
  *)
    GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
    PR_STATE_FILE="$GIT_COMMON_DIR/pr-validation/active-worktrees"

    # Raiz "canônica" do projeto: o primeiro worktree da lista do Git — no
    # padrão bare, é a própria entrada bare, e suas worktrees-irmãs (main
    # incluída) nascem dentro da pasta do projeto, exatamente como se quer.
    MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
    SIBLING_ROOT="$(dirname "$MAIN_ROOT")"
    ;;
esac

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

# Caminhos das entradas "bare" (sem working tree própria) na lista de
# worktrees — no padrão bare, a primeira entrada é sempre uma dessas, e não
# deve ser tratada como uma worktree de desenvolvimento comum.
worktrees_bare() {
  git worktree list --porcelain | awk '
    /^worktree /{ p=substr($0,10) }
    /^bare$/{ print p }
  '
}

esta_suja() {
  [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

case "$SUBCMD" in

  clone)
    [[ $# -ge 1 ]] || usage
    URL="$1"; shift
    DEST=""
    BR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dir)    DEST="${2:?--dir precisa de um valor}"; shift 2 ;;
        --branch) BR="${2:?--branch precisa de um valor}"; shift 2 ;;
        *) echo "Opção desconhecida: $1" >&2; usage ;;
      esac
    done

    if [[ -z "$DEST" ]]; then
      DEST="$(basename "$URL" .git)"
    fi
    [[ ! -e "$DEST" ]] || { echo "Já existe algo em '$DEST'. Abortando." >&2; exit 1; }

    echo "==> Clonando '$URL' (bare) em '$DEST/.bare'..."
    mkdir -p "$DEST"
    git clone --bare "$URL" "$DEST/.bare"
    echo "gitdir: ./.bare" > "$DEST/.git"
    # Sem isso, um clone --bare não guarda refs remotas para fetches futuros
    # nem o ponteiro refs/remotes/origin/HEAD (usado abaixo para achar a
    # branch padrão).
    git --git-dir="$DEST/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    git --git-dir="$DEST/.bare" fetch origin --quiet
    git --git-dir="$DEST/.bare" remote set-head origin --auto >/dev/null 2>&1 || true

    if [[ -z "$BR" ]]; then
      BR="$(git --git-dir="$DEST/.bare" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
      [[ -n "$BR" ]] || { echo "Não consegui detectar a branch padrão do remoto. Use --branch <nome>." >&2; exit 1; }
    fi

    echo "==> Criando worktree '$BR' (primeira do projeto)..."
    git -C "$DEST" worktree add "$BR" "$BR"

    echo
    echo "==> Pronto. Repositório clonado no padrão bare + worktree por branch."
    echo "    Repositório (bare): $DEST/.bare"
    echo "    Worktree:           $DEST/$BR"
    echo
    echo "    Próximas branches nascem como pastas irmãs dentro de '$DEST/'."
    echo "    Para entrar: cd \"$DEST/$BR\""
    ;;

  bootstrap-bare)
    ALVO="."
    CONFIRMOU_RISCOS=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --confirmo-riscos) CONFIRMOU_RISCOS=1; shift ;;
        --*) echo "Opção desconhecida: $1" >&2; usage ;;
        *) ALVO="$1"; shift ;;
      esac
    done

    REPO_ROOT="$(git -C "$ALVO" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$REPO_ROOT" ]] || { echo "'$ALVO' não é um repositório Git." >&2; exit 1; }

    if [[ "$(git -C "$REPO_ROOT" rev-parse --is-bare-repository)" == "true" ]]; then
      echo "'$REPO_ROOT' já é um repositório bare." >&2; exit 1
    fi
    if [[ "$(git -C "$REPO_ROOT" worktree list --porcelain | grep -c '^worktree ')" -gt 1 ]]; then
      echo "'$REPO_ROOT' já tem outras worktrees; converta manualmente ou peça ajuda." >&2
      exit 1
    fi
    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --ignored=no 2>/dev/null)" ]]; then
      echo "'$REPO_ROOT' tem alterações não salvas (tracked ou untracked):" >&2
      git -C "$REPO_ROOT" status --short >&2
      echo "Faça commit, stash ou limpe antes de converter." >&2
      exit 1
    fi

    # A checagem de árvore limpa acima não olha para arquivos ignorados
    # pelo .gitignore — mas a limpeza abaixo apaga TUDO que sobrar solto na
    # raiz, ignorado ou não. Por isso exige confirmação explícita: sem
    # --confirmo-riscos, só avisa e sai, sem mexer em nada.
    if [[ "$CONFIRMOU_RISCOS" -ne 1 ]]; then
      IGNORADOS="$(git -C "$REPO_ROOT" status --porcelain --ignored | awk '/^!! /{print substr($0,4)}')"
      {
        echo "==> ATENÇÃO: 'bootstrap-bare' reestrutura a raiz de '$REPO_ROOT' e isso NÃO é reversível."
        echo
        echo "    Depois de mover o .git para .bare, todo arquivo ou pasta que sobrar"
        echo "    solto na raiz é apagado — inclusive o que está no .gitignore (.env,"
        echo "    node_modules/, build/, chaves, credenciais locais etc). A checagem de"
        echo "    'árvore limpa' feita antes NÃO cobre esses arquivos: eles são"
        echo "    removidos do disco sem backup, mesmo a árvore estando limpa."
        echo
        if [[ -n "$IGNORADOS" ]]; then
          echo "    Arquivos/pastas ignorados encontrados na raiz agora (serão apagados):"
          while IFS= read -r item; do echo "      $item"; done <<<"$IGNORADOS"
          echo
        fi
        echo "    Confirme com o usuário que ele está ciente desse risco e quer seguir"
        echo "    mesmo assim. Só então rode de novo com --confirmo-riscos."
      } >&2
      exit 1
    fi

    BR="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "$BR" ]] || { echo "'$REPO_ROOT' está em HEAD detached; não dá para converter assim." >&2; exit 1; }

    SLUG="$(printf '%s' "$BR" | tr '/' '-' | tr -c 'a-zA-Z0-9._-' '-')"
    WORKTREE_PATH="$REPO_ROOT/$SLUG"
    [[ ! -e "$WORKTREE_PATH" ]] || { echo "Já existe algo em '$WORKTREE_PATH'. Abortando." >&2; exit 1; }

    echo "==> Convertendo '$REPO_ROOT' para bare + worktree por branch..."
    mv "$REPO_ROOT/.git" "$REPO_ROOT/.bare"
    git --git-dir="$REPO_ROOT/.bare" config core.bare true
    echo "gitdir: ./.bare" > "$REPO_ROOT/.git"

    # Os arquivos que estavam soltos na raiz (a antiga working tree) ficam
    # redundantes: a raiz não tem mais working tree própria. São removidos
    # só depois de o `.git` (que já era ponteiro) ser recriado — o que
    # importa (.bare) já está a salvo fora da raiz "solta".
    shopt -s dotglob nullglob
    for item in "$REPO_ROOT"/*; do
      base="$(basename "$item")"
      [[ "$base" == ".bare" || "$base" == ".git" ]] && continue
      rm -rf "$item"
    done
    shopt -u dotglob nullglob

    echo "==> Criando worktree '$BR'..."
    git -C "$REPO_ROOT" worktree add "$SLUG" "$BR"

    echo
    echo "==> Pronto. '$REPO_ROOT' agora é bare + worktree por branch."
    echo "    Repositório (bare): $REPO_ROOT/.bare"
    echo "    Worktree:           $WORKTREE_PATH"
    echo
    echo "    Próximas branches nascem como pastas irmãs aqui dentro."
    echo "    Para entrar: cd \"$WORKTREE_PATH\""
    ;;

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
    BARE_PATHS="$(worktrees_bare)"
    if [[ -n "$BARE_PATHS" ]]; then
      echo "=== REPOSITÓRIO (bare, sem working tree própria) ==="
      printf '%s\n' "$BARE_PATHS" | sed 's/^/  /'
      echo
    fi

    echo "=== WORKTREES DE DESENVOLVIMENTO ==="
    encontrou_dev=0
    echo "=== VALIDAÇÃO DE PR (descartáveis) ==="  >/dev/null  # ordem tratada abaixo
    DEV_OUT=""; PR_OUT=""
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      grep -qxF "$path" <<<"$BARE_PATHS" && continue  # entrada bare: já listada acima
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
    if [[ $# -ge 1 ]]; then
      ALVO="$1"
    else
      ALVO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      [[ -n "$ALVO" ]] || { echo "Rodando da raiz bare (sem working tree própria); informe a worktree: update <alvo>." >&2; exit 1; }
    fi
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

    # Sem working tree própria (rodando da raiz bare, por exemplo), não há
    # "cwd dentro de uma worktree" para comparar — segue sem essa checagem.
    ATUAL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -z "$ATUAL" ]] || [[ "$WT" != "$ATUAL" ]] || {
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
