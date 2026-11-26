#!/usr/bin/env bash
#
# Testes do install.sh. Usa um destino temporário (CLAUDE_SKILLS_DIR): não
# toca em ~/.claude/skills.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
nok() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
afirma() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
SKILLS=""
for f in "$ROOT"/skills/*/SKILL.md; do SKILLS="$SKILLS $(basename "$(dirname "$f")")"; done
afirma "o repositório tem skills em skills/" test -n "$SKILLS"

echo "install: links (padrão)"
D="$TMP/links"
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" >/dev/null 2>&1; RC=$?
afirma "sai com 0" test $RC -eq 0
for s in $SKILLS; do
  afirma "$s é um link para o checkout" test "$(readlink "$D/$s")" = "$ROOT/skills/$s"
  afirma "$s encontra o SKILL.md pelo link" test -f "$D/$s/SKILL.md"
done
afirma "não instala pastas sem SKILL.md (ex.: skills, tests, .github)" \
  test ! -e "$D/skills" -a ! -e "$D/tests" -a ! -e "$D/.github"
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" >/dev/null 2>&1; RC=$?
afirma "rodar de novo é idempotente" test $RC -eq 0
afirma "idempotente: sem backup quando já era link" test ! -e "$D/.backup"

echo "install: --copy e backup de versão antiga"
D="$TMP/copy"; mkdir -p "$D/pr-worktree"; echo antiga > "$D/pr-worktree/SKILL.md"
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" --copy >/dev/null 2>&1; RC=$?
afirma "sai com 0" test $RC -eq 0
afirma "pr-worktree é pasta de verdade, não link" test -d "$D/pr-worktree" -a ! -L "$D/pr-worktree"
afirma "conteúdo é o do repositório" cmp -s "$D/pr-worktree/SKILL.md" "$ROOT/skills/pr-worktree/SKILL.md"
afirma "versão antiga guardada em .backup (não apagada)" \
  bash -c "grep -rq antiga '$D/.backup'"
afirma "o .backup não vira uma segunda skill no diretório" test ! -e "$D/pr-worktree-backup"

echo "install: converte cópia em link"
D="$TMP/c2l"
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" --copy >/dev/null 2>&1
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" >/dev/null 2>&1
afirma "agora é link" test -L "$D/pr-worktree"

echo "install: troca o link do layout antigo (skill na raiz) pelo novo"
D="$TMP/antigo"; mkdir -p "$D"
ln -s "$ROOT/pr-worktree" "$D/pr-worktree"   # aponta para onde a skill ficava; hoje não existe
CLAUDE_SKILLS_DIR="$D" bash "$ROOT/install.sh" >/dev/null 2>&1; RC=$?
afirma "sai com 0" test $RC -eq 0
afirma "o link passa a apontar para skills/" test "$(readlink "$D/pr-worktree")" = "$ROOT/skills/pr-worktree"
afirma "o link antigo não vai para .backup" test ! -e "$D/.backup"

echo "install: opção inválida"
bash "$ROOT/install.sh" --nope >/dev/null 2>&1 && nok "recusa opção desconhecida" || ok "recusa opção desconhecida"

echo "install: via stdin (curl | bash) clona e instala"
REMOTE="$TMP/remote"; git init -q -b main "$REMOTE"
mkdir -p "$REMOTE/skills/minha-skill"; echo '---' > "$REMOTE/skills/minha-skill/SKILL.md"
cp "$ROOT/install.sh" "$REMOTE/install.sh"
git -C "$REMOTE" add -A; git -C "$REMOTE" commit -qm v1
D="$TMP/piped"; SRC="$TMP/piped-src"
CLAUDE_SKILLS_DIR="$D" CLAUDE_SKILLS_SRC="$SRC" SKILLS_REPO_URL="$REMOTE" bash < "$ROOT/install.sh" >/dev/null 2>&1; RC=$?
afirma "sai com 0" test $RC -eq 0
afirma "linkou a skill do clone" test "$(readlink "$D/minha-skill")" = "$SRC/skills/minha-skill"
echo novo > "$REMOTE/skills/minha-skill/extra.txt"; git -C "$REMOTE" add -A; git -C "$REMOTE" commit -qm v2
CLAUDE_SKILLS_DIR="$D" CLAUDE_SKILLS_SRC="$SRC" SKILLS_REPO_URL="$REMOTE" bash < "$ROOT/install.sh" >/dev/null 2>&1
afirma "rodar de novo faz pull e a skill ganha o arquivo novo" test -f "$D/minha-skill/extra.txt"

echo; echo "$PASS passaram, $FAIL falharam"
[[ "$FAIL" -eq 0 ]]
