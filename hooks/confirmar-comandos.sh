#!/usr/bin/env bash
# Hook PreToolUse (Bash) do plugin skills.
#
# Recebe no stdin o JSON da chamada e, se o comando for destrutivo, devolve
# permissionDecision "ask": o Claude Code mostra o pedido de confirmação
# mesmo com o comando liberado por regra ou no modo auto. Comandos comuns
# saem sem nada no stdout, e o fluxo normal de permissão segue.
#
# Pede confirmação para:
#   git push --force / -f / +refspec (o --force-with-lease passa)
#   git push para main ou master
#   git reset --hard
#   git clean com -f
#   git branch -D
#   rm com -r e -f juntos (-rf, -fr, -r -f, --recursive --force)

set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "confirmar-comandos: jq não encontrado; o hook não verificou o comando." >&2
  exit 1
fi

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Uma linha só, com espaços simples: facilita as regex.
flat=$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -s ' ')

GIT='(^|[;&|( ])git( +-[Cc] +[^ ]+)*'
motivos=()

if printf '%s' "$flat" | grep -Eq "$GIT +push( |$)"; then
  push=$(printf '%s' "$flat" | grep -Eo "$GIT +push[^;&|]*" | head -1)
  if printf '%s' "$push" | grep -Eq ' (--force|-f|-[a-zA-Z]*f[a-zA-Z]*)( |$)| \+[^ ]'; then
    motivos+=("git push forçado")
  fi
  if printf '%s' "$push" | grep -Eq '[ :](main|master)( |$)'; then
    motivos+=("push direto na main/master")
  fi
fi

printf '%s' "$flat" | grep -Eq "$GIT +reset( +[^ ;&|]+)* +--hard( |$)" &&
  motivos+=("git reset --hard")

printf '%s' "$flat" | grep -Eq "$GIT +clean( +[^ ;&|]+)* +(-[a-zA-Z]*f[a-zA-Z]*|--force)( |$)" &&
  motivos+=("git clean forçado")

printf '%s' "$flat" | grep -Eq "$GIT +branch( +[^ ;&|]+)* +-D( |$)" &&
  motivos+=("git branch -D")

# rm: junta as opções de cada ocorrência e confere se há recursivo e forçado.
segmentos=$(printf '%s' "$flat" | grep -Eo '(^|[;&|( ])(sudo +)?rm( +-[^ ;&|]+)+' || true)
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  opcoes=$(printf '%s' "$seg" | grep -Eo ' -[^ ]+' | tr -d ' ' | tr '\n' ' ')
  rec=0; frc=0
  for o in $opcoes; do
    case "$o" in
      --recursive) rec=1 ;;
      --force) frc=1 ;;
      --*) ;;
      -*)
        case "$o" in *[rR]*) rec=1 ;; esac
        case "$o" in *f*) frc=1 ;; esac
        ;;
    esac
  done
  if [ "$rec" = 1 ] && [ "$frc" = 1 ]; then
    motivos+=("rm recursivo forçado")
    break
  fi
done <<EOF
$segmentos
EOF

[ ${#motivos[@]} -gt 0 ] || exit 0

motivo=$(printf '%s, ' "${motivos[@]}")
motivo="Comando destrutivo (${motivo%, }): confirme explicitamente antes de rodar."

jq -n --arg r "$motivo" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
