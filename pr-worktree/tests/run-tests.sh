#!/usr/bin/env bash
#
# Testes de segurança de prepare/cleanup-pr-validation (repositório comum e
# layout bare) e, ao final, de manage-worktree.sh. Usa repositórios
# temporários (remoto bare + clone); não toca em nada fora do mktemp.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd)"
source "$HERE/helpers.sh"
hermetic_git_env

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-worktree-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

git init -q --bare -b main "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/work/repo" 2>/dev/null || { mkdir -p "$TMP/work"; git clone -q "$TMP/remote.git" "$TMP/work/repo"; }
cd "$TMP/work/repo" || exit 1
git checkout -q -b main 2>/dev/null || true
echo base > a.txt; git add .; git commit -qm base; git push -q origin main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || git remote set-head origin main
git checkout -q -b feat; echo pr > b.txt; echo changed >> a.txt; git add .; git commit -qm pr
git push -q origin feat; git checkout -q main

WT="$TMP/work/pr-review/pr-feat"
# shellcheck disable=SC2120  # os argumentos (--force) chegam via `check ... prep --force`
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
grep -q 'cleanup-pr-validation.sh' "$WT/CLAUDE.md" && ok "CLAUDE.md traz o caminho do script de cleanup" || nok "CLAUDE.md traz o caminho do script de cleanup"

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

echo "cleanup: --force e --all"
prep >/dev/null 2>&1; echo mine >> "$WT/a.txt"
# O motivo da recusa importa: um `--all` inexistente também "falharia".
check_fail_msg "--all preserva worktree com edição" "edições suas" cleanup --all
[[ -d "$WT" ]] && ok "--all deixou o worktree com edição no lugar" || nok "--all deixou o worktree com edição no lugar"
check "--force remove com edição" cleanup feat --force
prep >/dev/null 2>&1
check "--all remove os registrados sem edição" cleanup --all
[[ ! -d "$WT" ]] && ok "--all removeu o diretório" || nok "--all removeu o diretório"
check_fail_msg "--all sem nada registrado avisa" "Nenhum worktree" cleanup --all
check_fail_msg "--all não combina com alvo" "não combina" cleanup --all feat

echo "layout bare: prepare/cleanup"
BARE="$TMP/proj bare"            # com espaço de propósito
BWT="$BARE/pr-review/pr-feat"
git clone -q --bare "$TMP/remote.git" "$BARE/.bare"
git -C "$BARE/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$BARE/.bare" fetch -q origin
git -C "$BARE/.bare" remote set-head origin main >/dev/null
echo "gitdir: ./.bare" > "$BARE/.git"
git -C "$BARE" worktree add -q main main
bprep()  { ( cd "$1" && bash "$SCRIPTS/prepare-pr-validation.sh" feat --base main ); }
bclean() { local d="$1"; shift; ( cd "$d" && bash "$SCRIPTS/cleanup-pr-validation.sh" "$@" ); }
check "prepare a partir da raiz bare" bprep "$BARE"
[[ -d "$BWT" ]] && ok "worktree criado em <projeto>/pr-review/" || nok "worktree criado em <projeto>/pr-review/"
check "prepare a partir de uma worktree do projeto bare" bprep "$BARE/main"
check_fail_msg "cleanup recusa a partir de dentro do worktree" "dentro de" bclean "$BWT" feat
check_fail_msg "cleanup recusa a raiz bare" "repositório principal" bclean "$BARE" "$BARE"
check "cleanup a partir da raiz bare" bclean "$BARE" feat
[[ ! -d "$BWT" ]] && ok "diretório removido (bare)" || nok "diretório removido (bare)"
bprep "$BARE" >/dev/null 2>&1
check "cleanup --all a partir de uma worktree do projeto bare" bclean "$BARE/main" --all
[[ ! -d "$BWT" ]] && ok "--all removeu o diretório (bare)" || nok "--all removeu o diretório (bare)"
[[ -d "$BARE/.bare" && -d "$BARE/main" ]] && ok "projeto bare intacto" || nok "projeto bare intacto"

RC_PREPARE=0; resumo || RC_PREPARE=1

echo; echo "=== manage-worktree.sh ==="
RC_MANAGE=0; bash "$HERE/manage-worktree-tests.sh" || RC_MANAGE=1

[[ $RC_PREPARE -eq 0 && $RC_MANAGE -eq 0 ]]
