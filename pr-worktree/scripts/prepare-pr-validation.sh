#!/usr/bin/env bash
#
# prepare-pr-validation <feature-branch> [--base <base-branch>] [--force]
#
# Cria um worktree isolado, em HEAD *detached*, para revisar um PR sem
# jamais tocar a branch original (refs/heads/*). Dentro desse worktree,
# faz um `git reset` (mixed) até o merge-base com a branch alvo, para que
# o painel de alterações do editor mostre TODAS as alterações do PR de uma
# única vez — exatamente como no fluxo manual do usuário, mas seguro.
#
# Por que é seguro:
#   - `git worktree add --detach` nunca move/renomeia uma branch: ele só
#     posiciona o HEAD *deste worktree* num commit específico.
#   - HEAD e o índice (staging area) são armazenados por worktree, em
#     .git/worktrees/<nome>/HEAD e /index — não são compartilhados.
#   - Só objetos e refs/heads/* (as branches) são compartilhados entre
#     worktrees. Como nunca fazemos checkout *da branch* (só do commit,
#     detached), nenhuma branch é movida.
#
# Se já existir um worktree para o PR, ele só é recriado quando não tiver
# edições suas além do PR; --force recria mesmo assim, descartando-as.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-pr-validation.sh"

usage() {
  echo "Uso: prepare-pr-validation <feature-branch> [--base <base-branch>] [--force]" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
FEATURE_BRANCH="$1"; shift

BASE_BRANCH=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)    BASE_BRANCH="${2:?--base precisa de um valor}"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    --no-open) shift ;;  # aceito por compatibilidade; não faz mais nada
    -h|--help) usage ;;
    *) echo "Opção desconhecida: $1" >&2; usage ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
STATE_DIR="$GIT_COMMON_DIR/pr-validation"
mkdir -p "$STATE_DIR"

# Slug seguro para nome de pasta (troca "/" e outros caracteres por "-")
SLUG="$(printf '%s' "$FEATURE_BRANCH" | tr '/' '-' | tr -c 'a-zA-Z0-9._-' '-')"

# Worktrees ficam FORA da árvore do repo principal (pasta irmã), para não
# precisar de entradas no .gitignore e não confundir ferramentas que
# percorrem o diretório do repo.
WORKTREES_ROOT="$(dirname "$REPO_ROOT")/pr-review"
WORKTREE_PATH="${WORKTREES_ROOT}/pr-${SLUG}"

echo "==> Atualizando referência remota de '$FEATURE_BRANCH'..."
git fetch origin "$FEATURE_BRANCH" --quiet

if [[ -z "$BASE_BRANCH" ]]; then
  if command -v gh >/dev/null 2>&1; then
    echo "==> Detectando branch base via 'gh' (GitHub CLI)..."
    BASE_BRANCH="$(gh pr view "$FEATURE_BRANCH" --json baseRefName --jq '.baseRefName' 2>/dev/null || true)"
  fi
  if [[ -z "$BASE_BRANCH" ]]; then
    # fallback: branch padrão do remoto (main/master/develop, o que estiver configurado)
    BASE_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  fi
  if [[ -z "$BASE_BRANCH" ]]; then
    echo "Não foi possível detectar a branch base automaticamente." >&2
    echo "Informe explicitamente: prepare-pr-validation $FEATURE_BRANCH --base <branch>" >&2
    exit 1
  fi
fi

echo "==> Branch base: $BASE_BRANCH"
git fetch origin "$BASE_BRANCH" --quiet

MERGE_BASE="$(git merge-base "origin/${BASE_BRANCH}" "origin/${FEATURE_BRANCH}")"
PR_HEAD="$(git rev-parse "origin/${FEATURE_BRANCH}^{commit}")"
echo "==> Ponto de partida real do PR (merge-base): $MERGE_BASE"

# Se já existir um worktree para este PR, recria do zero (garante estado
# limpo) — mas só depois de conferir que não há edições do usuário nele.
if git worktree list --porcelain | grep -qx "worktree ${WORKTREE_PATH}"; then
  if [[ "$FORCE" -eq 0 ]]; then
    OLD_HEAD="$(registered_head "$WORKTREE_PATH" "$STATE_DIR/active-worktrees")"
    if [[ -z "$OLD_HEAD" ]]; then
      echo "Já existe um worktree para este PR e não dá para verificar se tem edições suas." >&2
      echo "Confira '$WORKTREE_PATH' e rode de novo com --force para recriá-lo." >&2
      exit 1
    fi
    CHANGES="$(local_changes "$WORKTREE_PATH" "$OLD_HEAD")"
    if [[ -n "$CHANGES" ]]; then
      echo "O worktree existente '$WORKTREE_PATH' tem edições suas além do PR:" >&2
      echo "$CHANGES" | sed 's/^/  /' >&2
      echo "Rode de novo com --force para recriá-lo (essas edições serão perdidas)." >&2
      exit 1
    fi
  fi
  echo "==> Worktree existente para este PR encontrado. Removendo antes de recriar..."
  git worktree remove --force "$WORKTREE_PATH"
elif [[ -e "$WORKTREE_PATH" ]]; then
  echo "Já existe algo em '$WORKTREE_PATH' que não é um worktree conhecido. Abortando por segurança." >&2
  exit 1
fi

mkdir -p "$WORKTREES_ROOT"

echo "==> Criando worktree isolado (HEAD detached) em: $WORKTREE_PATH"
git worktree add --detach "$WORKTREE_PATH" "$PR_HEAD"

echo "==> Populando o painel 'Changes' com o diff completo do PR (reset seguro, HEAD detached)..."
git -C "$WORKTREE_PATH" reset "$MERGE_BASE"

echo "==> Gerando CLAUDE.md com o contexto deste worktree..."
cat > "$WORKTREE_PATH/CLAUDE.md" <<EOF
# Ambiente de validação de PR — contexto para o Claude

Este diretório é um **worktree Git temporário e descartável**, criado apenas
para revisar, executar e testar um Pull Request. Não é o ambiente de
desenvolvimento normal do usuário.

## Estado do Git (intencional — não "corrigir")

- \`HEAD\` está **detached** de propósito.
- O índice foi resetado até o merge-base entre a branch do PR e a base, então
  o painel de alterações do editor / \`git status\` mostra TODAS as alterações
  do PR como não commitadas. Isso é esperado, não é um erro, e não deve ser
  "corrigido" com \`git commit\`, \`git add\` ou reanexando a uma branch.

- Branch do PR: ${FEATURE_BRANCH}
- Branch base: ${BASE_BRANCH}
- Merge-base (ponto de partida real do diff): ${MERGE_BASE}

> \`CLAUDE.md\` e \`PR-REVIEW.md\` na raiz são artefatos desta ferramenta e
> aparecem como arquivos não rastreados. **Não fazem parte do PR** e devem
> ser ignorados na revisão.

## O que você PODE fazer aqui

- Ler e analisar qualquer arquivo para revisão de código.
- Executar a aplicação e a suíte de testes normalmente.
- Comparar com a base a qualquer momento: \`git diff ${MERGE_BASE}\`
- Resumir o que o PR muda, apontar riscos, sugerir melhorias.

## O que você NÃO deve fazer aqui

- Não faça \`git commit\`, \`git push\`, \`git checkout <branch>\`, nem tente
  reanexar o HEAD a uma branch.
- Não tente mesclar, rebasear ou alterar a branch original a partir daqui —
  este worktree não tem relação de escrita com ela.
- Não rode \`cleanup-pr-validation\` a partir de dentro desta pasta: o comando
  apaga este diretório. Ele deve ser executado do repositório principal
  (${REPO_ROOT}), nunca daqui.

## Ao terminar a revisão

No terminal do repositório principal, não aqui:

    cleanup-pr-validation ${FEATURE_BRANCH}
EOF

# Registra o worktree ativo para o cleanup e para consultas futuras
{
  echo "$WORKTREE_PATH"
} > "$STATE_DIR/last-worktree"

if [[ -f "$STATE_DIR/active-worktrees" ]]; then
  awk -F'|' -v p="$WORKTREE_PATH" '$3 != p' "$STATE_DIR/active-worktrees" > "$STATE_DIR/active-worktrees.tmp"
  mv -f "$STATE_DIR/active-worktrees.tmp" "$STATE_DIR/active-worktrees"
fi
echo "${FEATURE_BRANCH}|${BASE_BRANCH}|${WORKTREE_PATH}|${MERGE_BASE}|${PR_HEAD}" >> "$STATE_DIR/active-worktrees"

echo
echo "==> Pronto."
echo "    PR (branch):   $FEATURE_BRANCH"
echo "    Base:          $BASE_BRANCH"
echo "    Merge-base:    $MERGE_BASE"
echo "    Worktree:      $WORKTREE_PATH  (HEAD detached — a branch original NÃO foi tocada)"
echo
echo "    Para entrar no worktree (abra-o no editor de sua preferência):"
echo "      cd \"$WORKTREE_PATH\""
echo
echo "    Para comparar manualmente com a base a qualquer momento:"
echo "      git -C \"$WORKTREE_PATH\" diff $MERGE_BASE"
echo
echo "    Para o relatório de revisão, use a skill 'branch-diff-report' com:"
echo "      base=$BASE_BRANCH  branch=$FEATURE_BRANCH  dir=$WORKTREE_PATH"
echo
echo "    Para finalizar e limpar:"
echo "      cleanup-pr-validation \"$FEATURE_BRANCH\""

