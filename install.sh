#!/usr/bin/env bash
#
# install.sh [--copy] [--help]
#
# Instala as skills deste repositório (toda pasta com um SKILL.md na raiz) em
# ~/.claude/skills.
#
#   padrão   cria um link simbólico por skill apontando para este checkout:
#            atualizar a skill = atualizar o repositório (git pull / update da
#            worktree main), sem rodar o instalador de novo.
#   --copy   copia as pastas (a skill instalada não acompanha o repositório).
#
# Rodado por `curl ... | bash` (sem checkout ao lado), clona o repositório em
# ~/.claude/skills-src e instala a partir dele; rodar de novo faz git pull.
#
# Variáveis: CLAUDE_SKILLS_DIR (destino), CLAUDE_SKILLS_SRC (onde clonar),
# SKILLS_REPO_URL (de onde clonar).
#
set -euo pipefail

MODE=link
for arg in "$@"; do
  case "$arg" in
    --copy) MODE=copy ;;
    -h|--help) awk 'NR >= 3 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "Opção desconhecida: $arg (use --copy ou --help)" >&2; exit 1 ;;
  esac
done

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

SELF="${BASH_SOURCE[0]:-}"
REPO_DIR=""
if [[ -n "$SELF" && -f "$SELF" ]]; then
  REPO_DIR="$(cd "$(dirname "$SELF")" && pwd)"
fi

# Sem checkout ao lado do script (curl | bash): clona ou atualiza um.
if [[ -z "$REPO_DIR" ]] || ! compgen -G "$REPO_DIR/*/SKILL.md" >/dev/null; then
  SRC="${CLAUDE_SKILLS_SRC:-$HOME/.claude/skills-src}"
  URL="${SKILLS_REPO_URL:-https://github.com/carlosdoria/skills.git}"
  if [[ -d "$SRC/.git" ]]; then
    echo "==> Atualizando $SRC"
    git -C "$SRC" pull --ff-only --quiet
  else
    echo "==> Clonando $URL em $SRC"
    git clone --quiet "$URL" "$SRC"
  fi
  REPO_DIR="$SRC"
fi

mkdir -p "$SKILLS_DIR"
BACKUP_DIR="$SKILLS_DIR/.backup"
STAMP="$(date +%Y%m%d-%H%M%S)"
INSTALADAS=0

for skill_file in "$REPO_DIR"/*/SKILL.md; do
  [[ -f "$skill_file" ]] || continue
  skill_dir="$(dirname "$skill_file")"
  name="$(basename "$skill_dir")"
  target="$SKILLS_DIR/$name"

  # Uma cópia antiga (pasta de verdade) vai para .backup em vez de ser apagada:
  # pode ter edição local. Um link antigo é só substituído.
  if [[ -L "$target" ]]; then
    rm "$target"
  elif [[ -e "$target" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$target" "$BACKUP_DIR/$name-$STAMP"
    echo "    (versão anterior de '$name' guardada em $BACKUP_DIR/$name-$STAMP)"
  fi

  if [[ "$MODE" == copy ]]; then
    cp -R "$skill_dir" "$target"
    echo "✅ $name (cópia)"
  else
    ln -s "$skill_dir" "$target"
    echo "✅ $name -> $skill_dir"
  fi
  INSTALADAS=$((INSTALADAS + 1))
done

if [[ "$INSTALADAS" -eq 0 ]]; then
  echo "Nenhuma skill encontrada em '$REPO_DIR' (esperava */SKILL.md)." >&2
  exit 1
fi

echo
echo "$INSTALADAS skill(s) instalada(s) em: $SKILLS_DIR"
if [[ "$MODE" == link ]]; then
  BR="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || true)"
  echo "Os links apontam para '$REPO_DIR'${BR:+ (branch $BR)}: o que estiver"
  echo "nessa pasta é o que o Claude Code usa. Para atualizar, atualize o repositório."
  [[ -z "$BR" || "$BR" == main ]] || echo "Atenção: esse checkout não está na main."
fi
echo "Abra uma nova sessão do Claude Code para carregá-las."
