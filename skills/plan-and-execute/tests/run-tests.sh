#!/usr/bin/env bash
#
# Testes estruturais da skill plan-and-execute: frontmatter válido e as
# seções que o SKILL.md promete (7 fases, cada uma com critério de saída,
# hard gate, anti-padrões). A parte comportamental fica em tests/evals.md.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$DIR/SKILL.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
nok() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

if [[ ! -f "$SKILL" ]]; then
  echo "  FAIL SKILL.md não encontrado em $DIR"
  exit 1
fi

# --- Frontmatter -----------------------------------------------------------
head -1 "$SKILL" | grep -qx -- '---' && ok "frontmatter abre com ---" || nok "frontmatter abre com ---"

FM="$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$SKILL")"
grep -qx "name: $(basename "$DIR")" <<<"$FM" \
  && ok "name bate com o nome da pasta" || nok "name bate com o nome da pasta"

DESC="$(grep '^description:' <<<"$FM" | sed 's/^description: *//')"
[[ -n "$DESC" ]] && ok "description presente" || nok "description presente"
[[ "${#DESC}" -le 1024 ]] && ok "description cabe em 1024 caracteres" || nok "description cabe em 1024 caracteres"
grep -q 'Use sempre que' <<<"$DESC" && ok "description traz gatilhos de uso" || nok "description traz gatilhos de uso"

# --- Seções obrigatórias ---------------------------------------------------
for sec in "## Princípios" "## Anti-padrões" "## Integração com outras skills" "Quando não usar"; do
  grep -qF "$sec" "$SKILL" && ok "seção '$sec'" || nok "seção '$sec'"
done

for n in 1 2 3 4 5 6 7; do
  grep -qE "^## Fase $n — " "$SKILL" && ok "Fase $n presente" || nok "Fase $n presente"
done

# Cada fase declara objetivo e critério de saída.
OBJ="$(grep -c '^\*\*Objetivo:\*\*' "$SKILL")"
SAIDA="$(grep -c '^\*\*Saída da fase:\*\*' "$SKILL")"
[[ "$OBJ" -eq 7 ]] && ok "7 fases com objetivo" || nok "7 fases com objetivo (achou $OBJ)"
[[ "$SAIDA" -eq 7 ]] && ok "7 fases com critério de saída" || nok "7 fases com critério de saída (achou $SAIDA)"

grep -qF 'HARD GATE' "$SKILL" && ok "hard gate de aprovação do design" || nok "hard gate de aprovação do design"

# A tabela de anti-padrões tem pelo menos 5 linhas de conteúdo.
ANTI="$(awk '/^## Anti-padrões/, /^## Integração/' "$SKILL" | grep -c '^| "')"
[[ "$ANTI" -ge 5 ]] && ok "tabela de anti-padrões com conteúdo" || nok "tabela de anti-padrões com conteúdo (achou $ANTI)"

echo
echo "$PASS passaram, $FAIL falharam"
[[ "$FAIL" -eq 0 ]]
