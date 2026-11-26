# Claude Code Skills

Coleção de skills para o [Claude Code](https://claude.com/claude-code).

## Skills disponíveis

| Skill | Descrição |
| --- | --- |
| [`branch-diff-report`](branch-diff-report/SKILL.md) | Compara duas branches e gera um relatório de revisão a partir do diff. |
| [`plan-and-execute`](plan-and-execute/SKILL.md) | Processo operacional para tarefas não triviais: entender, desenhar com aprovação, planejar, executar e verificar com evidência. |
| [`pr-worktree`](pr-worktree/SKILL.md) | Gerencia worktrees Git (bare + worktree por branch) e valida Pull Requests localmente. |

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/carlosdoria/skills/main/install.sh | bash
```

Isso clona o repositório em `~/.claude/skills-src` e cria, em
`~/.claude/skills/`, um link simbólico por skill apontando para ele.

Alternativa clonando o repositório você mesmo:

```bash
git clone git@github.com:carlosdoria/skills.git && cd skills && ./install.sh
```

Os links apontam para esse checkout. Se ele for um projeto bare + worktree por
branch, rode o `install.sh` a partir da worktree `main`.

Abra uma nova sessão do Claude Code para que sejam carregadas.

### Atualizar

Com a instalação por link (padrão), atualizar a skill é atualizar o
repositório que os links apontam: `git pull` (ou `update` da worktree `main`).
Não é preciso rodar o instalador de novo. Se instalou via `curl | bash`, rodar
o comando de novo faz o `git pull` em `~/.claude/skills-src`.

`./install.sh --copy` copia as pastas em vez de linkar; nesse modo a skill
instalada **não** acompanha o repositório e precisa ser reinstalada a cada
mudança. Uma pasta já existente em `~/.claude/skills` é guardada em
`~/.claude/skills/.backup/`, não apagada.

### Testar uma branch antes do merge

Rode `./install.sh` a partir da worktree da branch: os links passam a apontar
para ela. Depois do merge, rode de novo a partir da `main`.

## Estrutura

```text
skills/
├── branch-diff-report/
│   ├── SKILL.md
│   ├── references/
│   ├── scripts/
│   ├── templates/
│   └── tests/
├── plan-and-execute/
│   ├── SKILL.md
│   └── tests/
└── pr-worktree/
    ├── SKILL.md
    ├── references/
    ├── scripts/
    └── tests/
```

O `SKILL.md` fica com o que todo uso precisa; o que só alguns pedidos usam
vai para `references/`, lido sob demanda, para gastar menos tokens.

## Requisitos

- Bash
- Git (>= 2.17 para a `pr-worktree`, que usa `git worktree remove`)
- Claude Code

O `gh` (GitHub CLI), autenticado, é usado para consultar PRs no GitHub:
detectar a branch base, achar um PR por descrição e publicar o resumo. Sem
ele, as skills pedem as branches ao usuário.

## Testes e CI

Cada skill tem seus testes em `<skill>/tests/run-tests.sh`, em repositórios
temporários; rode-os depois de alterar os scripts:

- `branch-diff-report`: seções e limites da saída, sinalizadores, branch
  mergeada, somente leitura, sem temporários.
- `pr-worktree`: segurança do prepare/cleanup (repositório comum e layout
  bare) e o `manage-worktree.sh` (`tests/manage-worktree-tests.sh`, que
  também roda sozinho).

O instalador tem `tests/test-install.sh`. O workflow `.github/workflows/tests.yml` roda tudo em
cada PR e a cada push na `main`, no macOS (Bash 3.2) e no Ubuntu. O job de
`shellcheck` (`-S warning`) também precisa passar.

Para exigir que o PR só entre com os testes verdes, ative em *Settings ›
Branches* uma regra de proteção para `main` com os checks `tests (macos-latest)`,
`tests (ubuntu-latest)` e `shellcheck` como obrigatórios.

## Melhorias futuras

- [ ] Documentar processo de contribuição (`CONTRIBUTING.md`) para novas skills.
- [ ] Adicionar versionamento/changelog das skills.
