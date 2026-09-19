#!/usr/bin/env bash
#
# collect-branch-facts <base-branch> <feature-branch> [--dir <caminho>] [--no-fetch]
#
# Coleta fatos BRUTOS e determinísticos sobre a diferença entre duas
# branches. Não interpreta nada, não classifica risco, não escreve
# relatório: apenas extrai dados verificáveis do Git, em seções
# delimitadas, para que a camada de julgamento (a skill) monte o
# relatório em cima disso.
#
# Somente leitura: não cria worktree, não altera refs, não toca no
# working tree. Funciona em qualquer repositório Git.
#
#   --dir      repositório/worktree onde operar (padrão: diretório atual)
#   --no-fetch pula o `git fetch` (útil offline ou em repo já atualizado)
#
set -euo pipefail

usage() {
  echo "Uso: collect-branch-facts <base-branch> <feature-branch> [--dir <caminho>] [--no-fetch]" >&2
  exit 1
}

[[ $# -ge 2 ]] || usage
BASE_BRANCH="$1"; shift
FEATURE_BRANCH="$1"; shift

WORK_DIR="."
DO_FETCH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)      WORK_DIR="${2:?--dir precisa de um valor}"; shift 2 ;;
    --no-fetch) DO_FETCH=0; shift ;;
    -h|--help)  usage ;;
    *) echo "Opção desconhecida: $1" >&2; usage ;;
  esac
done

[[ -d "$WORK_DIR" ]] || { echo "Diretório não encontrado: $WORK_DIR" >&2; exit 1; }

g() { git -C "$WORK_DIR" "$@"; }

g rev-parse --git-dir >/dev/null 2>&1 || { echo "'$WORK_DIR' não é um repositório Git." >&2; exit 1; }

if [[ "$DO_FETCH" -eq 1 ]] && g remote get-url origin >/dev/null 2>&1; then
  g fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
  g fetch origin "$FEATURE_BRANCH" --quiet 2>/dev/null || true
fi

# Resolve uma branch para um commit, preferindo a versão do remoto.
resolver_ref() {
  local nome="$1" sha=""
  sha="$(g rev-parse --verify --quiet "origin/${nome}^{commit}" || true)"
  [[ -n "$sha" ]] || sha="$(g rev-parse --verify --quiet "${nome}^{commit}" || true)"
  printf '%s' "$sha"
}

BASE_SHA="$(resolver_ref "$BASE_BRANCH")"
PR_HEAD="$(resolver_ref "$FEATURE_BRANCH")"

if [[ -z "$BASE_SHA" ]]; then
  echo "Branch base não encontrada: '$BASE_BRANCH' (nem local, nem em origin/)." >&2
  exit 1
fi
if [[ -z "$PR_HEAD" ]]; then
  echo "Branch de comparação não encontrada: '$FEATURE_BRANCH' (nem local, nem em origin/)." >&2
  exit 1
fi

MERGE_BASE="$(g merge-base "$BASE_SHA" "$PR_HEAD" 2>/dev/null || true)"
if [[ -z "$MERGE_BASE" ]]; then
  echo "As branches '$BASE_BRANCH' e '$FEATURE_BRANCH' não têm ancestral comum." >&2
  exit 1
fi

if [[ "$MERGE_BASE" == "$PR_HEAD" ]]; then
  echo "=== META ==="
  echo "aviso: '$FEATURE_BRANCH' não tem nenhum commit à frente de '$BASE_BRANCH'."
  echo "=== FIM ==="
  exit 0
fi

WORKTREE_PATH="$(g rev-parse --show-toplevel)"


echo "=== META ==="
echo "base_branch: $BASE_BRANCH"
echo "feature_branch: $FEATURE_BRANCH"
echo "merge_base: $MERGE_BASE"
echo "pr_head: $PR_HEAD"
echo "repo: $WORKTREE_PATH"
echo "gerado_em: $(date '+%Y-%m-%d %H:%M')"

echo
echo "=== AUTORES ==="
g log --format='%an' "${MERGE_BASE}..${PR_HEAD}" | sort | uniq -c | sort -rn

echo
echo "=== COMMITS ==="
g log --format='%h %s' "${MERGE_BASE}..${PR_HEAD}"

echo
echo "=== TOTAIS ==="
g diff --shortstat "$MERGE_BASE" "$PR_HEAD"

echo
echo "=== ARQUIVOS (status<TAB>adicoes<TAB>remocoes<TAB>caminho) ==="
# Junta name-status (A/M/D/R) com numstat (+/-) numa linha só por arquivo.
g diff --name-status -M "$MERGE_BASE" "$PR_HEAD" > /tmp/.pr_status.$$ || true
g diff --numstat   -M "$MERGE_BASE" "$PR_HEAD" > /tmp/.pr_numstat.$$ || true
awk -F'\t' '
  NR==FNR { st[$NF]=$1; next }
  { path=$NF; printf "%s\t%s\t%s\t%s\n", (st[path]?st[path]:"?"), $1, $2, path }
' /tmp/.pr_status.$$ /tmp/.pr_numstat.$$
rm -f /tmp/.pr_status.$$ /tmp/.pr_numstat.$$

echo
echo "=== ARQUIVOS MAIS ALTERADOS (top 10 por linhas tocadas) ==="
g diff --numstat -M "$MERGE_BASE" "$PR_HEAD" \
  | awk -F'\t' '$1 ~ /^[0-9]+$/ { print $1+$2 "\t" $3 }' \
  | sort -rn | head -10

echo
echo "=== SINALIZADORES (arquivos sensiveis tocados) ==="
g diff --name-only -M "$MERGE_BASE" "$PR_HEAD" | while IFS= read -r f; do
  case "$f" in
    *migration*|*migrations/*|*.sql)                    echo "migracao_ou_sql: $f" ;;
    .env*|*.env|*config*|*.yml|*.yaml|*.toml|*.ini)     echo "configuracao: $f" ;;
    *lock*|package-lock.json|yarn.lock|pnpm-lock.yaml)  echo "lockfile: $f" ;;
    .github/*|*Dockerfile*|*docker-compose*)            echo "ci_ou_infra: $f" ;;
    *auth*|*Auth*|*permission*|*Permission*|*token*)    echo "auth_ou_permissao: $f" ;;
    *webhook*|*Webhook*)                                echo "endpoint_publico: $f" ;;
  esac
done

echo
echo "=== MANIFESTOS DE DEPENDENCIA (diff bruto) ==="
DEP_FILES="$(g diff --name-only -M "$MERGE_BASE" "$PR_HEAD" \
  | grep -E '(^|/)(package\.json|requirements\.txt|pyproject\.toml|go\.mod|Gemfile|composer\.json|Cargo\.toml)$' || true)"
if [[ -z "$DEP_FILES" ]]; then
  echo "(nenhum manifesto de dependencia alterado)"
else
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    echo "--- $f"
    g diff -U0 "$MERGE_BASE" "$PR_HEAD" -- "$f" | grep -E '^[+-][^+-]' || true
  done <<< "$DEP_FILES"
fi

echo
echo "=== TESTES NO DIFF ==="
ALL="$(g diff --name-only -M "$MERGE_BASE" "$PR_HEAD")"
TESTS="$(printf '%s\n' "$ALL" | grep -Ei '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[jt]sx?$|_test\.(py|go|rb)$|Test\.(java|php|cs)$' || true)"
SRC="$(printf '%s\n' "$ALL" \
  | grep -Ei '\.(js|jsx|ts|tsx|py|go|rb|java|php|cs|kt|swift|rs|vue|svelte)$' || true)"
SRC_NAO_TESTE="$(comm -23 <(printf '%s\n' "$SRC" | sort -u) <(printf '%s\n' "$TESTS" | sort -u))"

echo "arquivos_de_teste_no_diff:"
printf '%s\n' "$TESTS" | sed '/^$/d' | sed 's/^/  /' || true
echo "arquivos_de_codigo_sem_teste_homonimo_no_diff:"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  stem="$(basename "$f")"; stem="${stem%.*}"
  if ! printf '%s\n' "$TESTS" | grep -qi -- "$stem"; then
    echo "  $f"
  fi
done <<< "$SRC_NAO_TESTE"

echo
echo "=== COMPONENTES (heuristica: arquivos PascalCase de UI) ==="
COMPONENTES="$(printf '%s\n' "$ALL" \
  | grep -E '\.(tsx|jsx|vue|svelte)$' \
  | grep -E '(^|/)[A-Z][A-Za-z0-9]*\.(tsx|jsx|vue|svelte)$' || true)"
HOOKS="$(printf '%s\n' "$ALL" | grep -E '(^|/)use[A-Z][A-Za-z0-9]*\.[jt]sx?$' || true)"
ALVOS="$(printf '%s\n%s\n' "$COMPONENTES" "$HOOKS" | sed '/^$/d' | sort -u)"

if [[ -z "$ALVOS" ]]; then
  echo "(nenhum componente/hook identificado pela heuristica)"
else
  N="$(printf '%s\n' "$ALVOS" | wc -l | tr -d ' ')"
  if (( N > 40 )); then
    echo "(muitos componentes alterados: $N — contagem de consumidores pulada por performance)"
    printf '%s\n' "$ALVOS" | sed 's/^/  /'
  else
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      nome="$(basename "$f")"; nome="${nome%.*}"
      status="$(g diff --name-status -M "$MERGE_BASE" "$PR_HEAD" -- "$f" | cut -f1 | head -1)"
      # Conta consumidores na árvore da branch de comparação, não no
      # working tree — assim o resultado independe do que está em disco.
      consumidores="$(g grep -l -w "$nome" "$PR_HEAD" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.vue' '*.svelte' 2>/dev/null \
        | sed "s|^${PR_HEAD}:||" | grep -vFx "$f" | wc -l | tr -d ' ' || true)"
      consumidores="${consumidores:-0}"
      echo "  ${status:-M}	${nome}	${f}	consumidores=${consumidores}"
    done <<< "$ALVOS"
  fi
fi

echo
echo "=== FIM ==="
