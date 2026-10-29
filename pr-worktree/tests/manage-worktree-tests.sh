#!/usr/bin/env bash
#
# Testes de manage-worktree.sh (clone, bootstrap-bare, new, list, update,
# remove). Usa um remoto bare local e pastas temporárias com espaço no nome;
# não toca em nada fora do mktemp. Pode ser rodado sozinho ou via run-tests.sh.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd)"
source "$HERE/helpers.sh"
hermetic_git_env

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-worktree-manage-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

MW() { bash "$SCRIPTS/manage-worktree.sh" "$@"; }
em() { local d="$1"; shift; ( cd "$d" && "$@" ); }

# git "falso" no PATH: registra as chamadas e simula falhas sob demanda.
#   FAKE_STATUS_FAIL=1  `git status` sai com erro
#   FAKE_ADD_FAIL=1     `git worktree add` sai com erro
#   FAKE_GIT_LOG=<arq>  acrescenta os argumentos de cada chamada
REAL_GIT="$(command -v git)"
export REAL_GIT
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/git" <<'EOF'
#!/usr/bin/env bash
has() { local want="$1" w; shift; for w in "$@"; do [[ "$w" == "$want" ]] && return 0; done; return 1; }
if [[ "${FAKE_STATUS_FAIL:-0}" == 1 ]] && has status "$@"; then echo "fatal: simulado" >&2; exit 128; fi
if [[ "${FAKE_ADD_FAIL:-0}" == 1 ]] && has worktree "$@" && has add "$@"; then echo "fatal: simulado" >&2; exit 128; fi
[[ -z "${FAKE_GIT_LOG:-}" ]] || echo "$*" >> "$FAKE_GIT_LOG"
exec "$REAL_GIT" "$@"
EOF
chmod +x "$TMP/fakebin/git"
fake() { PATH="$TMP/fakebin:$PATH" "$@"; }

# --- remoto com main e feature/x, e um clone "semente" para empurrar commits ---
git init -q --bare -b main "$TMP/remote.git"
git init -q -b main "$TMP/seed"
git -C "$TMP/seed" remote add origin "$TMP/remote.git"
echo base > "$TMP/seed/a.txt"; printf '.env\nnode_modules/\n' > "$TMP/seed/.gitignore"
git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm base; git -C "$TMP/seed" push -q origin main
git -C "$TMP/seed" checkout -q -b feature/x; echo x > "$TMP/seed/x.txt"
git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm x; git -C "$TMP/seed" push -q origin feature/x
git -C "$TMP/seed" checkout -q main
seed_push() { # <branch> <arquivo> — empurra um commit novo para o remoto
  git -C "$TMP/seed" checkout -q "$1"; echo "$RANDOM" >> "$TMP/seed/$2"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm "mais $2"; git -C "$TMP/seed" push -q origin "$1"
  git -C "$TMP/seed" checkout -q main
}

PROJ="$TMP/proj dir"            # espaço de propósito

echo "clone"
check "clone cria o projeto bare" MW clone "$TMP/remote.git" --dir "$PROJ"
afirma "estrutura .bare + ponteiro .git + main/" test -d "$PROJ/.bare" -a -f "$PROJ/.git" -a -d "$PROJ/main"
afirma "a worktree está na branch padrão" test "$(git -C "$PROJ/main" symbolic-ref --short HEAD)" = main
check_fail_msg "clone recusa destino existente" "Já existe" MW clone "$TMP/remote.git" --dir "$PROJ"

echo "new"
check "new a partir da worktree main (pasta irmã por padrão)" em "$PROJ/main" MW new feature/y
afirma "worktree criada ao lado, com o nome derivado" test -d "$PROJ/feature-y"
afirma "branch nova existe" git -C "$PROJ/main" show-ref --verify --quiet refs/heads/feature/y
afirma "nasce do mesmo commit de origin/main" \
  test "$(git -C "$PROJ/feature-y" rev-parse HEAD)" = "$(git -C "$PROJ/main" rev-parse origin/main)"
check_fail_msg "new recusa branch que já existe" "já existe" em "$PROJ/main" MW new feature/y
check_fail_msg "new recusa pasta que já existe" "Já existe algo" em "$PROJ/main" MW new feature/q --dir "$PROJ/feature-y"
check "new com --dir de caminho com espaço" em "$PROJ/main" MW new feature/z --from "$PROJ/main" --dir "$PROJ/custom z"
afirma "worktree criada no --dir" test -d "$PROJ/custom z"
check "new a partir da raiz bare" em "$PROJ" MW new feature/r --from main
afirma "irmã criada dentro do projeto" test -d "$PROJ/feature-r"
echo dirty >> "$PROJ/main/a.txt"
check_msg "new não toca na base com alterações não salvas" "não vou tocá-la" em "$PROJ/main" MW new feature/w --from "$PROJ/main"
afirma "alteração da base preservada" grep -q dirty "$PROJ/main/a.txt"
git -C "$PROJ/main" checkout -q -- a.txt

echo "list"
OUT="$(em "$PROJ" MW list 2>&1)"
grep -q "REPOSITÓRIO (bare" <<<"$OUT" && ok "list mostra a entrada bare" || { nok "list mostra a entrada bare"; mostrar "$OUT"; }
grep -q "feature/y" <<<"$OUT" && ok "list mostra a worktree de desenvolvimento" || { nok "list mostra a worktree de desenvolvimento"; mostrar "$OUT"; }
grep -q "(nenhuma)" <<<"$OUT" && ok "list indica que não há validação de PR" || { nok "list indica que não há validação de PR"; mostrar "$OUT"; }
echo d >> "$PROJ/feature-y/a.txt"
check_msg "list marca alterações não salvas" "feature/y.*alterações não salvas" em "$PROJ" MW list
git -C "$PROJ/feature-y" checkout -q -- a.txt
rm -rf "$PROJ/custom z"
check_msg "list sinaliza pasta apagada à mão" "ausente.*git worktree prune" em "$PROJ" MW list
git -C "$PROJ" worktree prune

echo "update"
seed_push main a.txt
check_msg "update faz fast-forward" "fast-forward" em "$PROJ/main" MW update "$PROJ/main"
afirma "HEAD igual ao do remoto" \
  test "$(git -C "$PROJ/main" rev-parse HEAD)" = "$(git -C "$TMP/seed" rev-parse main)"
check_msg "update repetido: já atualizada" "Já atualizada" em "$PROJ/main" MW update "$PROJ/main"
echo d >> "$PROJ/main/a.txt"
check_fail_msg "update recusa worktree com alterações" "alterações não salvas" em "$PROJ/main" MW update "$PROJ/main"
git -C "$PROJ/main" checkout -q -- a.txt
git -C "$PROJ" worktree add -q "$PROJ/fx" feature/x
echo local > "$PROJ/fx/local.txt"; git -C "$PROJ/fx" add -A; git -C "$PROJ/fx" commit -qm local
check_msg "update com commit local só à frente não força nada" "à frente" em "$PROJ/main" MW update "$PROJ/fx"
seed_push feature/x x.txt
check_fail_msg "update recusa pontas divergentes" "divergiram" em "$PROJ/main" MW update "$PROJ/fx"

echo "remove"
echo d >> "$PROJ/feature-y/a.txt"
check_fail_msg "remove recusa worktree suja" "alterações não salvas" em "$PROJ/main" MW remove "$PROJ/feature-y"
afirma "worktree suja continua no lugar" test -d "$PROJ/feature-y"
git -C "$PROJ/feature-y" checkout -q -- a.txt
check_fail_msg "remove falha fechado se o git status falhar" "alterações não salvas" \
  env FAKE_STATUS_FAIL=1 PATH="$TMP/fakebin:$PATH" bash -c "cd '$PROJ/main' && bash '$SCRIPTS/manage-worktree.sh' remove '$PROJ/feature-y'"
afirma "worktree não removida quando o status falha" test -d "$PROJ/feature-y"
check_fail_msg "remove recusa estar dentro da worktree" "dentro de" em "$PROJ/feature-y" MW remove "$PROJ/feature-y"
check_fail_msg "remove recusa opção desconhecida" "Opção desconhecida" em "$PROJ/main" MW remove "$PROJ/feature-r" --forc

: > "$TMP/gitlog"
check "remove de worktree limpa" env FAKE_GIT_LOG="$TMP/gitlog" PATH="$TMP/fakebin:$PATH" \
  bash -c "cd '$PROJ/main' && bash '$SCRIPTS/manage-worktree.sh' remove '$PROJ/feature-r'"
afirma "worktree removida" test ! -d "$PROJ/feature-r"
afirma "branch preservada" git -C "$PROJ/main" show-ref --verify --quiet refs/heads/feature/r
afirma "sem --force não repassa --force ao git" \
  bash -c "grep -q 'worktree remove' '$TMP/gitlog' && ! grep -q 'worktree remove --force' '$TMP/gitlog'"
check_msg "branch sem commits novos: informa que já foi mesclada" "já foi mesclada" \
  em "$PROJ/main" MW remove "$PROJ/feature-w"

: > "$TMP/gitlog"
echo d >> "$PROJ/feature-y/a.txt"
check "--force antes do alvo funciona" env FAKE_GIT_LOG="$TMP/gitlog" PATH="$TMP/fakebin:$PATH" \
  bash -c "cd '$PROJ/main' && bash '$SCRIPTS/manage-worktree.sh' remove --force '$PROJ/feature-y'"
afirma "com --force repassa --force ao git" grep -q 'worktree remove --force' "$TMP/gitlog"
afirma "worktree suja removida com --force" test ! -d "$PROJ/feature-y"

git -C "$PROJ" worktree add -q --detach "$PROJ/det" main
echo orfao > "$PROJ/det/o.txt"; git -C "$PROJ/det" add -A; git -C "$PROJ/det" commit -qm orfao
check_fail_msg "remove recusa detached com commit fora de qualquer branch" "HEAD detached" em "$PROJ/main" MW remove "$PROJ/det"
afirma "worktree detached continua no lugar" test -d "$PROJ/det"
check "--force remove o detached" em "$PROJ/main" MW remove "$PROJ/det" --force
git -C "$PROJ" worktree add -q --detach "$PROJ/det2" main
check "remove de detached cujo commit está numa branch" em "$PROJ/main" MW remove "$PROJ/det2"

echo "bootstrap-bare"
mk_repo() {
  git clone -q "$TMP/remote.git" "$1" 2>/dev/null
  printf 'segredo\n' > "$1/.env"; mkdir -p "$1/node_modules"; echo mod > "$1/node_modules/m.js"
}
R="$TMP/repo conv"
mk_repo "$R"
check_rc "sem --confirmo-riscos só avisa (código 3)" 3 em "$R" MW bootstrap-bare
check_fail_msg "o aviso lista os ignorados que serão movidos" "\.env" em "$R" MW bootstrap-bare
afirma "nada mudou depois do aviso" test -d "$R/.git" -a -f "$R/.env" -a -f "$R/a.txt"

echo u > "$R/u.txt"
check_fail_msg "recusa árvore com arquivo não rastreado" "alterações não salvas" em "$R" MW bootstrap-bare --confirmo-riscos
git -C "$R" config status.showUntrackedFiles no
check_fail_msg "recusa mesmo com status.showUntrackedFiles=no" "alterações não salvas" em "$R" MW bootstrap-bare --confirmo-riscos
git -C "$R" config --unset status.showUntrackedFiles; rm "$R/u.txt"

: > "$R/.gitmodules"; git -C "$R" add .gitmodules; git -C "$R" commit -qm submodulos
check_fail_msg "recusa repositório com submódulos" "submódulos" em "$R" MW bootstrap-bare --confirmo-riscos
git -C "$R" reset -q --hard HEAD~1

check_fail_msg "recusa converter a \$HOME" "não é uma pasta de projeto" env HOME="$R" bash "$SCRIPTS/manage-worktree.sh" bootstrap-bare "$R" --confirmo-riscos
afirma "repositório intacto depois das recusas" test -d "$R/.git" -a -f "$R/.env" -a -f "$R/a.txt"

check_not "falha na criação da worktree desfaz a conversão" fake env FAKE_ADD_FAIL=1 bash "$SCRIPTS/manage-worktree.sh" bootstrap-bare "$R" --confirmo-riscos
afirma ".git voltou a ser a pasta do repositório" test -d "$R/.git"
afirma "arquivos versionados e ignorados voltaram à raiz" test -f "$R/a.txt" -a -f "$R/.env" -a -f "$R/node_modules/m.js"
afirma "sem .bare nem staging sobrando" bash -c "[[ ! -e '$R/.bare' ]] && ! ls -d '$R'/.bootstrap-old.* >/dev/null 2>&1"
afirma "repositório volta a ser não-bare e limpo" \
  bash -c "[[ \"\$(git -C '$R' config core.bare)\" == false && -z \"\$(git -C '$R' status --porcelain)\" ]]"

check "converte com --confirmo-riscos" em "$R" MW bootstrap-bare --confirmo-riscos
afirma "estrutura .bare + ponteiro .git + worktree main" test -d "$R/.bare" -a -f "$R/.git" -a -d "$R/main"
afirma "o repositório em .bare é bare" test "$(git --git-dir="$R/.bare" rev-parse --is-bare-repository)" = true
afirma "arquivo versionado está na worktree" test -f "$R/main/a.txt"
afirma ".env (ignorado) foi movido para a worktree, com o conteúdo" test "$(cat "$R/main/.env" 2>/dev/null)" = segredo
afirma "node_modules/ (ignorado) foi movido para a worktree" test -f "$R/main/node_modules/m.js"
afirma "a worktree não tem alterações" test -z "$(git -C "$R/main" status --porcelain)"
afirma "o conteúdo antigo ficou preservado em .bootstrap-old.*" bash -c "ls -d '$R'/.bootstrap-old.* >/dev/null 2>&1"
check_not "converter de novo não é possível" em "$R" MW bootstrap-bare --confirmo-riscos
check "new funciona no projeto convertido" em "$R/main" MW new feature/conv
afirma "irmã criada dentro do projeto convertido" test -d "$R/feature-conv"

echo "usage"
check_fail_msg "usage mostra o cabeçalho inteiro (inclusive os códigos de saída)" "Códigos de saída" bash "$SCRIPTS/manage-worktree.sh"

resumo
