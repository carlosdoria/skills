#!/usr/bin/env bash
#
# Testes de segurança de prepare/cleanup-pr-validation. Usa repositórios
# temporários (remoto bare + clone); não toca em nada fora do mktemp.
#
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-worktree-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
nok()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else nok "$d"; fi; }
check_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then nok "$d"; else ok "$d"; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare -b main "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/work/repo" 2>/dev/null || { mkdir -p "$TMP/work"; git clone -q "$TMP/remote.git" "$TMP/work/repo"; }
cd "$TMP/work/repo"
git checkout -q -b main 2>/dev/null || true
echo base > a.txt; git add .; git commit -qm base; git push -q origin main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || git remote set-head origin main
git checkout -q -b feat; echo pr > b.txt; echo changed >> a.txt; git add .; git commit -qm pr
git push -q origin feat; git checkout -q main

WT="$TMP/work/pr-review/pr-feat"
prep()    { bash "$SCRIPTS/prepare-pr-validation.sh" feat --base main "$@"; }
cleanup() { bash "$SCRIPTS/cleanup-pr-validation.sh" "$@"; }

echo "prepare: base não detectável"
git remote set-head origin -d >/dev/null
OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPTS/prepare-pr-validation.sh" feat 2>&1)"; RC=$?
[[ $RC -ne 0 ]] && ok "falha sem base detectável" || nok "falha sem base detectável"
grep -q "Informe explicitamente" <<<"$OUT" && ok "pede --base em vez de sair calado" || nok "pede --base em vez de sair calado"
git remote set-head origin main >/dev/null

echo "prepare"
check "cria o worktree" prep
check "registra o commit do PR (5º campo)" bash -c "awk -F'|' '{exit \$5 == \"\"}' .git/pr-validation/active-worktrees"
check "recria quando não há edições" prep

echo "prepare: edição do usuário"
echo mine >> "$WT/a.txt"
check_not "recusa recriar com edição" prep
grep -q mine "$WT/a.txt" && ok "edição preservada" || nok "edição preservada"
check "--force recria" prep --force

echo "cleanup: proteções"
echo new > "$WT/user-file.txt"
check_not "recusa arquivo novo do usuário" cleanup feat
[[ -d "$WT" ]] && ok "worktree preservado" || nok "worktree preservado"
check_not "recusa a partir de dentro do worktree" bash -c "cd '$WT' && bash '$SCRIPTS/cleanup-pr-validation.sh' '$WT'"
check_not "recusa caminho fora do registro" cleanup "$TMP/work"
check_not "recusa o repositório principal" cleanup "$TMP/work/repo"
[[ -d "$TMP/work/repo/.git" ]] && ok "repositório principal intacto" || nok "repositório principal intacto"
rm "$WT/user-file.txt"

echo "cleanup: caminho feliz"
check "remove worktree sem edições" cleanup feat
[[ ! -d "$WT" ]] && ok "diretório removido" || nok "diretório removido"
git show-ref --verify --quiet refs/heads/feat && ok "branch preservada" || nok "branch preservada"

echo "cleanup: --force"
prep >/dev/null 2>&1; echo mine >> "$WT/a.txt"
check_not "--all preserva worktree com edição" cleanup --all
check "--force remove com edição" cleanup feat --force

echo; echo "$PASS passaram, $FAIL falharam"
[[ "$FAIL" -eq 0 ]]
