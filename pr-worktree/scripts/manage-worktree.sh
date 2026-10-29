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
#       branch. Recusa se a árvore não estiver limpa (inclusive arquivos
#       não rastreados), se o caminho for a $HOME ou /, ou se houver
#       submódulos. A branch atualmente com checkout na raiz (padrão:
#       repositório do diretório atual) vira uma worktree irmã.
#       Nada é apagado: o conteúdo antigo da raiz é movido para uma pasta
#       .bootstrap-old.XXXXXX dentro do projeto e os arquivos ignorados
#       pelo .gitignore (.env, node_modules/ ...) são movidos para a
#       worktree nova. Se a criação da worktree falhar, tudo volta ao lugar.
#       Como a estrutura do projeto muda (caminhos que apontavam para a
#       raiz passam a apontar para a worktree), só roda com
#       --confirmo-riscos: sem a flag, imprime o aviso e sai com código 3
#       sem mexer em nada. Mostre o aviso ao usuário e só use a flag depois
#       que ele confirmar de forma explícita.
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
#       Remove a worktree e, se a branch dela já foi mesclada, informa
#       (a branch nunca é apagada). Recusa se houver trabalho não salvo —
#       inclusive commits de uma worktree em HEAD detached que não estão em
#       nenhuma branch/tag. --force pode vir em qualquer posição.
#
# <alvo> pode ser o caminho da worktree ou o nome da branch.
# Worktrees ficam em uma pasta irmã à raiz do repositório principal — que,
# no padrão bare (clone/bootstrap-bare), é a própria pasta do projeto, já
# que ela não tem mais working tree própria.
#
# Códigos de saída: 0 ok; 1 erro ou recusa de proteção; 3 precisa de
# confirmação do usuário (bootstrap-bare sem --confirmo-riscos).
#
set -euo pipefail

# Imprime o bloco de comentários do cabeçalho (a partir da linha 3, até o
# primeiro comentário que não seja contíguo), sem depender de intervalo fixo.
usage() {
  awk 'NR >= 3 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0" >&2
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

# Falha fechada: se o `git status` não roda (índice corrompido, dono
# diferente, diretório ausente...), não dá para provar que a worktree está
# limpa — então conta como suja.
esta_suja() {
  local out
  out="$(git -C "$1" status --porcelain 2>/dev/null)" || return 0
  [[ -n "$out" ]]
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

    # Uma pasta pessoal ou a raiz do disco nunca é "um projeto": a conversão
    # mexeria em tudo que está dentro dela (ex.: dotfiles versionados na $HOME).
    HOME_REAL="$(cd "$HOME" 2>/dev/null && pwd -P || true)"
    if [[ "$REPO_ROOT" == "/" || ( -n "$HOME_REAL" && "$REPO_ROOT" == "$HOME_REAL" ) ]]; then
      echo "Recuso converter '$REPO_ROOT': não é uma pasta de projeto." >&2; exit 1
    fi

    if [[ "$(git -C "$REPO_ROOT" rev-parse --is-bare-repository)" == "true" ]]; then
      echo "'$REPO_ROOT' já é um repositório bare." >&2; exit 1
    fi
    if [[ ! -d "$REPO_ROOT/.git" ]]; then
      echo "'$REPO_ROOT/.git' não é uma pasta (worktree vinculada ou submódulo); não converto." >&2; exit 1
    fi
    if [[ -e "$REPO_ROOT/.gitmodules" ]]; then
      echo "'$REPO_ROOT' tem submódulos (.gitmodules); a conversão não os trata. Converta manualmente." >&2; exit 1
    fi
    if [[ "$(git -C "$REPO_ROOT" worktree list --porcelain | grep -c '^worktree ')" -gt 1 ]]; then
      echo "'$REPO_ROOT' já tem outras worktrees; converta manualmente ou peça ajuda." >&2
      exit 1
    fi
    # assume-unchanged / skip-worktree (e sparse-checkout) escondem modificações
    # do `git status`: não dá para provar que a árvore está limpa.
    # (sem `grep -q` no pipe: com pipefail um SIGPIPE esconderia o match)
    ESCONDIDOS="$(git -C "$REPO_ROOT" ls-files -v | grep '^[a-zS]' || true)"
    if [[ -n "$ESCONDIDOS" ]]; then
      echo "'$REPO_ROOT' tem arquivos marcados como assume-unchanged/skip-worktree (ou sparse-checkout);" >&2
      echo "o status não mostra tudo que mudou. Desmarque-os antes de converter." >&2
      exit 1
    fi
    # --untracked-files=all vale mesmo com status.showUntrackedFiles=no.
    STATUS="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" \
      || { echo "Não consegui ler o status de '$REPO_ROOT'; não converto." >&2; exit 1; }
    if [[ -n "$STATUS" ]]; then
      echo "'$REPO_ROOT' tem alterações não salvas (tracked ou untracked):" >&2
      git -C "$REPO_ROOT" status --short --untracked-files=all >&2
      echo "Faça commit, stash ou limpe antes de converter." >&2
      exit 1
    fi

    BR="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "$BR" ]] || { echo "'$REPO_ROOT' está em HEAD detached; não dá para converter assim." >&2; exit 1; }

    SLUG="$(printf '%s' "$BR" | tr '/' '-' | tr -c 'a-zA-Z0-9._-' '-')"
    WORKTREE_PATH="$REPO_ROOT/$SLUG"
    [[ ! -e "$WORKTREE_PATH" ]] || {
      echo "Já existe algo em '$WORKTREE_PATH' (é onde a worktree da branch '$BR' seria criada). Abortando." >&2; exit 1; }

    # Arquivos/pastas ignorados pelo .gitignore (.env, node_modules/, build/...):
    # a checagem de árvore limpa não os cobre e o Git não os recria. Eles são
    # movidos para a worktree nova, não descartados.
    IGNORADOS=()
    while IFS= read -r -d '' item; do
      IGNORADOS+=("$item")
    done < <(git -C "$REPO_ROOT" ls-files --others --ignored --exclude-standard --directory -z)

    # Reestrutura a pasta do projeto (caminhos mudam): exige confirmação
    # explícita. Sem --confirmo-riscos só avisa e sai (código 3), sem mexer em nada.
    if [[ "$CONFIRMOU_RISCOS" -ne 1 ]]; then
      {
        echo "==> ATENÇÃO: 'bootstrap-bare' vai reestruturar '$REPO_ROOT'."
        echo
        echo "    - O .git vira .bare (repositório bare); a raiz deixa de ter working tree própria."
        echo "    - A branch '$BR' passa a viver na worktree '$WORKTREE_PATH'."
        echo "    - Nada é apagado: o conteúdo atual da raiz vai para uma pasta temporária"
        echo "      (.bootstrap-old.XXXXXX, dentro do projeto) e os arquivos ignorados pelo"
        echo "      .gitignore são movidos para a worktree nova. Se algo falhar, tudo volta"
        echo "      ao lugar."
        echo "    - Caminhos que apontavam para '$REPO_ROOT' (editor aberto, terminais,"
        echo "      scripts, atalhos) passam a precisar apontar para '$WORKTREE_PATH'."
        echo
        if [[ ${#IGNORADOS[@]} -gt 0 ]]; then
          echo "    Arquivos/pastas ignorados que serão movidos para a worktree nova:"
          for item in "${IGNORADOS[@]}"; do echo "      $item"; done
          echo
        fi
        echo "    Confirme com o usuário que ele quer reestruturar o projeto assim."
        echo "    Só então rode de novo com --confirmo-riscos."
      } >&2
      exit 3
    fi

    echo "==> Convertendo '$REPO_ROOT' para bare + worktree por branch..."
    STAGE="$(mktemp -d "$REPO_ROOT/.bootstrap-old.XXXXXX")"
    STAGE_NAME="${STAGE##*/}"
    BOOTSTRAP_ATIVO=1

    # Se qualquer passo falhar antes de a worktree existir, devolve tudo ao
    # lugar: nada foi apagado, então a restauração é só mover de volta.
    desfazer_bootstrap() {
      local rc=$?
      [[ "${BOOTSTRAP_ATIVO:-0}" -eq 1 ]] || return 0
      trap - EXIT INT TERM HUP
      set +e
      echo "==> Falhou (código $rc); restaurando '$REPO_ROOT' ao estado anterior..." >&2
      git --git-dir="$REPO_ROOT/.bare" worktree prune 2>/dev/null
      rm -rf "$WORKTREE_PATH"   # não existia antes da conversão (checado acima)
      [[ -f "$REPO_ROOT/.git" ]] && rm -f "$REPO_ROOT/.git"
      shopt -s dotglob nullglob
      for item in "$STAGE"/*; do mv "$item" "$REPO_ROOT/${item##*/}"; done
      shopt -u dotglob nullglob
      [[ -d "$REPO_ROOT/.bare" ]] && mv "$REPO_ROOT/.bare" "$REPO_ROOT/.git"
      git --git-dir="$REPO_ROOT/.git" config core.bare false
      rmdir "$STAGE" 2>/dev/null
      exit "$rc"
    }
    trap desfazer_bootstrap EXIT
    trap 'exit 130' INT TERM HUP

    mv "$REPO_ROOT/.git" "$REPO_ROOT/.bare"
    git --git-dir="$REPO_ROOT/.bare" config core.bare true
    printf 'gitdir: ./.bare\n' > "$REPO_ROOT/.git"

    shopt -s dotglob nullglob
    for item in "$REPO_ROOT"/*; do
      base="${item##*/}"
      case "$base" in .bare|.git|"$STAGE_NAME") continue ;; esac
      mv "$item" "$STAGE/$base"
    done
    shopt -u dotglob nullglob

    echo "==> Criando worktree '$BR'..."
    git -C "$REPO_ROOT" worktree add "$SLUG" "$BR"
    BOOTSTRAP_ATIVO=0
    trap - EXIT INT TERM HUP

    for ign in ${IGNORADOS[@]+"${IGNORADOS[@]}"}; do
      ign="${ign%/}"
      [[ -e "$STAGE/$ign" || -L "$STAGE/$ign" ]] || continue
      if [[ -e "$WORKTREE_PATH/$ign" || -L "$WORKTREE_PATH/$ign" ]]; then
        echo "    ('$ign' já existe na worktree nova; a cópia antiga continua em '$STAGE')" >&2
        continue
      fi
      mkdir -p "$(dirname "$WORKTREE_PATH/$ign")"
      mv "$STAGE/$ign" "$WORKTREE_PATH/$ign" \
        || echo "    (não consegui mover '$ign'; ele continua em '$STAGE')" >&2
    done

    echo
    echo "==> Pronto. '$REPO_ROOT' agora é bare + worktree por branch."
    echo "    Repositório (bare): $REPO_ROOT/.bare"
    echo "    Worktree:           $WORKTREE_PATH"
    echo "    Conteúdo antigo:    $STAGE"
    echo "                        (cópia dos arquivos versionados; depois de conferir, apague:"
    echo "                         rm -rf \"$STAGE\")"
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
    DEV_OUT=""; PR_OUT=""
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      grep -qxF "$path" <<<"$BARE_PATHS" && continue  # entrada bare: já listada acima
      if [[ -d "$path" ]]; then
        branch="$(branch_da_worktree "$path")"
        sujo=""; esta_suja "$path" && sujo="  [alterações não salvas]"
      else
        # Pasta apagada à mão: o Git ainda registra a worktree.
        branch="(ausente)"; sujo="  [pasta não existe mais; rode git worktree prune]"
      fi
      linha="  ${branch}	${path}${sujo}"
      if eh_worktree_de_pr "$path"; then
        PR_OUT+="$linha"$'\n'
      else
        DEV_OUT+="$linha"$'\n'
      fi
    done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')

    printf '%s' "${DEV_OUT:-  (nenhuma)
}"
    echo
    echo "=== VALIDAÇÃO DE PR (descartáveis) ==="
    printf '%s' "${PR_OUT:-  (nenhuma)
}"
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
    FORCE=0; ALVO=""
    for a in "$@"; do
      case "$a" in
        --force) FORCE=1 ;;
        -*) echo "Opção desconhecida: $a" >&2; usage ;;
        *)  [[ -z "$ALVO" ]] || { echo "Só um alvo por vez; recebi '$ALVO' e '$a'." >&2; exit 1; }
            ALVO="$a" ;;
      esac
    done
    [[ -n "$ALVO" ]] || usage

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

    # Worktree detached cujo commit não está em nenhuma branch/tag/remoto: os
    # commits só existem aqui e somem junto com a pasta.
    if [[ "$BR" == "(detached)" && "$FORCE" -eq 0 \
          && -z "$(git -C "$WT" for-each-ref --contains HEAD --count=1 refs/heads refs/remotes refs/tags 2>/dev/null)" ]]; then
      echo "A worktree '$WT' está em HEAD detached e o commit atual não está em nenhuma branch/tag:" >&2
      echo "remover perde esse trabalho. Crie uma branch (git -C \"$WT\" switch -c <nome>) ou use --force." >&2
      exit 1
    fi

    echo "==> Removendo worktree: $WT"
    # --force só quando o usuário pediu (e já foi avisado do que se perde).
    if [[ "$FORCE" -eq 1 ]]; then
      git worktree remove --force "$WT"
    else
      git worktree remove "$WT"
    fi
    git worktree prune

    if [[ "$BR" != "(detached)" ]] && git show-ref --verify --quiet "refs/heads/${BR}"; then
      # "Mesclada" é em relação à branch padrão do remoto, não ao HEAD de
      # quem rodou o comando.
      REF_PADRAO="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
      if [[ -z "$REF_PADRAO" ]]; then
        echo "==> A branch '$BR' foi preservada (não detectei a branch padrão para saber se já foi mesclada)."
      elif git for-each-ref --merged="$REF_PADRAO" --format='%(refname:short)' "refs/heads/${BR}" 2>/dev/null | grep -qxF "$BR"; then
        echo "==> A branch '$BR' já foi mesclada em '$REF_PADRAO' e continua existindo."
        echo "    Para apagá-la também: git branch -d \"$BR\""
      else
        echo "==> A branch '$BR' foi preservada (tem commits não mesclados em '$REF_PADRAO')."
      fi
    fi
    echo "==> Limpeza concluída."
    ;;

  *)
    echo "Subcomando desconhecido: $SUBCMD" >&2
    usage
    ;;
esac
