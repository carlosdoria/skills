#!/usr/bin/env bash
# Testes do hooks/confirmar-comandos.sh: cada caso manda um payload como o
# do Claude Code e confere se o hook pede confirmação ("ask") ou deixa passar.

set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DIR/confirmar-comandos.sh"
falhas=0
total=0

roda() {
  jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK"
}

pede() {
  total=$((total + 1))
  saida=$(roda "$1")
  if printf '%s' "$saida" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1; then
    echo "  ok   pede confirmação: $1"
  else
    echo "  FAIL deveria pedir confirmação: $1"
    falhas=$((falhas + 1))
  fi
}

passa() {
  total=$((total + 1))
  saida=$(roda "$1")
  if [ -z "$saida" ]; then
    echo "  ok   passa: $1"
  else
    echo "  FAIL deveria passar: $1 -> $saida"
    falhas=$((falhas + 1))
  fi
}

echo "confirmar-comandos.sh"

pede 'git push --force'
pede 'git push -f origin feat/x'
pede 'git push origin +feat/x'
pede 'git -C ~/repo push --force origin feat/x'
pede 'git push origin main'
pede 'git push origin HEAD:main'
pede 'git push origin master'
pede 'git reset --hard'
pede 'git reset --hard origin/main'
pede 'git clean -fd'
pede 'git clean -xdf'
pede 'git branch -D feat/x'
pede 'rm -rf build'
pede 'rm -fr build'
pede 'rm -Rf build'
pede 'rm -r -f build'
pede 'rm --recursive --force build'
pede 'sudo rm -rf /tmp/x'
pede 'cd /tmp && rm -rf x'
pede 'npm test; git push --force'
pede $'echo ok\nrm -rf dist'

passa 'git push'
passa 'git push origin feat/x'
passa 'git push --force-with-lease origin feat/x'
passa 'git push -u origin feat/main-menu'
passa 'git reset --soft HEAD~1'
passa 'git clean -n'
passa 'git branch -d feat/x'
passa 'rm -r build'
passa 'rm -f arquivo.txt'
passa 'rm arquivo.txt'
passa 'ls -rf'
passa 'echo "git push --force" > notas.txt'
passa 'git status'

# Payload sem comando: sai sem nada.
total=$((total + 1))
if [ -z "$(echo '{"tool_name":"Bash","tool_input":{}}' | bash "$HOOK")" ]; then
  echo "  ok   payload sem comando passa"
else
  echo "  FAIL payload sem comando"
  falhas=$((falhas + 1))
fi

echo
echo "$((total - falhas))/$total passaram"
[ "$falhas" -eq 0 ]
