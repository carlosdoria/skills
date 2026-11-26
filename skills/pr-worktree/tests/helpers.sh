#!/usr/bin/env bash
#
# Funções compartilhadas pelos testes. Feito para ser lido com `source`.
#
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
nok() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Em falha, mostra a saída do comando: sem isso um teste vermelho não diz o
# motivo (e um teste verde pode ser verde pelo motivo errado).
mostrar() { [[ -z "$1" ]] || sed 's/^/       | /' <<<"$1"; }

# check <descrição> <comando...>      passa se o comando sai com 0
check() {
  local d="$1" out; shift
  if out="$("$@" 2>&1)"; then ok "$d"; else nok "$d"; mostrar "$out"; fi
}
# check_not <descrição> <comando...>  passa se o comando sai com erro
check_not() {
  local d="$1" out; shift
  if out="$("$@" 2>&1)"; then nok "$d"; mostrar "$out"; else ok "$d"; fi
}
# check_fail_msg <descrição> <regex> <comando...>
#   passa se o comando sai com erro E a saída casa com a regex — evita passar
#   "porque falhou" por um motivo qualquer.
check_fail_msg() {
  local d="$1" re="$2" out; shift 2
  if out="$("$@" 2>&1)"; then nok "$d (deveria falhar)"; mostrar "$out"
  elif grep -qE -- "$re" <<<"$out"; then ok "$d"
  else nok "$d (falhou, mas a mensagem não casa com /$re/)"; mostrar "$out"; fi
}
# check_msg <descrição> <regex> <comando...>  passa se sai com 0 E a saída casa
check_msg() {
  local d="$1" re="$2" out; shift 2
  if ! out="$("$@" 2>&1)"; then nok "$d (saiu com erro)"; mostrar "$out"
  elif grep -qE -- "$re" <<<"$out"; then ok "$d"
  else nok "$d (a saída não casa com /$re/)"; mostrar "$out"; fi
}
# check_rc <descrição> <código> <comando...>
check_rc() {
  local d="$1" want="$2" out rc; shift 2
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$d"; else nok "$d (código $rc, esperado $want)"; mostrar "$out"; fi
}
# afirma <descrição> <comando de teste...>   ex.: afirma "existe" test -d /tmp
afirma() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }

# Isola dos arquivos de configuração do usuário (gpgsign, hooks, aliases,
# init.defaultBranch...) e fixa a identidade dos commits.
hermetic_git_env() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

resumo() {
  echo; echo "$PASS passaram, $FAIL falharam"
  [[ "$FAIL" -eq 0 ]]
}
