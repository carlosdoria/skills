# Padrão bare: clonar e converter

Caminhos `scripts/...` relativos à pasta da skill. Antes do `clone`,
confirme a pasta com o usuário (regra no SKILL.md).

## Projeto novo

```bash
bash scripts/manage-worktree.sh clone <url> [--dir <destino>] [--branch <nome>]
```

Clona direto como bare em `<destino>/.bare` e cria a worktree da branch
padrão do remoto em `<destino>/<branch>`. Sempre que o usuário pedir para
clonar um repositório, use isso em vez de `git clone`.

## Projeto já clonado do jeito antigo (checkout direto na raiz)

```bash
bash scripts/manage-worktree.sh bootstrap-bare [<caminho>] [--confirmo-riscos]
```

Converte em lugar, criando `.bare` e uma worktree para a branch que estava
com checkout.

- **Recusa se a árvore não estiver limpa** (inclusive arquivos não
  rastreados), se o caminho for a `$HOME` ou `/`, ou se houver submódulos
  ou arquivos `assume-unchanged`/`skip-worktree`. Resolva com o usuário
  antes; nunca descarte nada por conta própria.
- **Nada é apagado:** o conteúdo antigo da raiz vai para
  `.bootstrap-old.XXXXXX` dentro do projeto, e os arquivos ignorados pelo
  `.gitignore` (`.env`, `node_modules/`, build local, chaves...) vão para a
  worktree nova. Se a criação da worktree falhar, tudo volta ao lugar.
- Como os caminhos do projeto mudam (editor, terminais e scripts que
  apontavam para a raiz passam a apontar para a worktree), o comando exige
  `--confirmo-riscos`. Sem a flag, ele só mostra o aviso, com a lista dos
  arquivos ignorados que serão movidos, e sai com **código 3** sem mexer em
  nada.
- **Mostre o aviso completo ao usuário, sem resumir, e só rode de novo com
  `--confirmo-riscos` depois que ele confirmar explicitamente** que quer
  reestruturar o projeto. Nunca adicione a flag por conta própria, mesmo
  com a árvore limpa.
- Ao terminar, diga onde ficou o `.bootstrap-old.*`; quem apaga é o
  usuário, depois de conferir a worktree nova.

Depois de bare, `new`, `list`, `update` e `remove` funcionam como no
SKILL.md.
