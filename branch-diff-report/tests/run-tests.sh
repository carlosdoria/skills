#!/usr/bin/env bash
#
# Testes de collect-branch-facts: seções esperadas, somente leitura e sem
# lixo em /tmp.
#
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/collect-branch-facts.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/facts-tests.XXXXXX")"
TMPDIR_ISOLADO="$TMP/tmpdir"; mkdir -p "$TMPDIR_ISOLADO"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
nok() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main "$TMP/repo"; cd "$TMP/repo" || exit 1
echo a > a.txt; git add .; git commit -qm base
git checkout -q -b feat; echo b > b.txt; echo x >> a.txt
mkdir -p .github/workflows; echo x > .github/workflows/ci.yml; echo x > pnpm-lock.yaml
echo x > docker-compose.yml; echo x > settings.yml; echo x > blockchain.ts
git add .; git commit -qm feat
git checkout -q main
BEFORE="$(git status --porcelain; git rev-parse HEAD feat main)"

OUT="$(TMPDIR="$TMPDIR_ISOLADO" bash "$SCRIPT" main feat --no-fetch 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "termina com sucesso" || nok "termina com sucesso"
for sec in "=== META ===" "=== COMMITS ===" "=== ARQUIVOS"; do
  grep -qF "$sec" <<<"$OUT" && ok "seção $sec" || nok "seção $sec"
done
grep -q $'^A\t1\t0\tb.txt' <<<"$OUT" && ok "arquivo adicionado listado" || nok "arquivo adicionado listado"
# Sinalizadores: o padrão mais específico vence (antes *.yml/*.yaml engoliam os outros).
grep -qx 'lockfile: pnpm-lock.yaml' <<<"$OUT" && ok "pnpm-lock.yaml é lockfile" || nok "pnpm-lock.yaml é lockfile"
grep -qx 'ci_ou_infra: .github/workflows/ci.yml' <<<"$OUT" && ok "workflow do GitHub é ci_ou_infra" || nok "workflow do GitHub é ci_ou_infra"
grep -qx 'ci_ou_infra: docker-compose.yml' <<<"$OUT" && ok "docker-compose.yml é ci_ou_infra" || nok "docker-compose.yml é ci_ou_infra"
grep -qx 'configuracao: settings.yml' <<<"$OUT" && ok "outro .yml continua configuracao" || nok "outro .yml continua configuracao"
grep -q 'lockfile: blockchain.ts' <<<"$OUT" && nok "blockchain.ts não é lockfile" || ok "blockchain.ts não é lockfile"
[[ -z "$(ls -A "$TMPDIR_ISOLADO")" ]] && ok "não deixa temporários" || nok "não deixa temporários"
[[ "$BEFORE" == "$(git status --porcelain; git rev-parse HEAD feat main)" ]] && ok "somente leitura" || nok "somente leitura"

bash "$SCRIPT" main nao-existe --no-fetch >/dev/null 2>&1 && nok "branch inexistente falha" || ok "branch inexistente falha"

echo; echo "$PASS passaram, $FAIL falharam"
[[ "$FAIL" -eq 0 ]]
