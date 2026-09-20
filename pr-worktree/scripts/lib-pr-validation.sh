#!/usr/bin/env bash
#
# Funções compartilhadas por prepare-pr-validation e cleanup-pr-validation.
# Feito para ser lido com `source`, não executado.
#
# Registro (.git/pr-validation/active-worktrees), uma linha por worktree:
#   branch|base|caminho|merge-base|pr-head
# `pr-head` é o commit do PR no momento do prepare; entradas antigas não o
# têm e, por isso, não dá para provar que o worktree está sem edições.

# Caminho físico (sem symlinks) de um diretório existente.
abs_dir() { (cd "$1" 2>/dev/null && pwd -P); }

# Imprime o PR-head registrado para o caminho, ou nada.
registered_head() {
  local path="$1" file="$2"
  [[ -f "$file" ]] || return 0
  awk -F'|' -v p="$path" '$3 == p { h=$5 } END { if (h) print h }' "$file"
}

# 0 se o caminho consta no registro.
is_registered() {
  local path="$1" file="$2"
  [[ -f "$file" ]] && awk -F'|' -v p="$path" '$3 == p { f=1 } END { exit !f }' "$file"
}

# Lista os arquivos do worktree que diferem do PR-head, ou seja, edições do
# usuário. O reset (mixed) deixa TODO o PR como "não commitado", então o
# status do Git não serve: compara-se cada arquivo com o conteúdo do PR.
# CLAUDE.md e PR-REVIEW.md são artefatos da ferramenta e são ignorados.
local_changes() {
  local wt="$1" head="$2" f
  git -C "$wt" ls-files -m -o -d --exclude-standard | sort -u | while IFS= read -r f; do
    case "$f" in CLAUDE.md|PR-REVIEW.md) continue ;; esac
    if [[ -f "$wt/$f" ]]; then
      git -C "$wt" cat-file -e "${head}:${f}" 2>/dev/null \
        && git -C "$wt" show "${head}:${f}" | cmp -s - "$wt/$f" && continue
      echo "$f"
    else
      # sumiu do disco: só é edição se o PR contém o arquivo
      git -C "$wt" cat-file -e "${head}:${f}" 2>/dev/null && echo "$f"
    fi
  done
  return 0
}
