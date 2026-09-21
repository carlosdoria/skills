# Claude Code Skills

Coleção de skills para o [Claude Code](https://claude.com/claude-code).

## Skills disponíveis

| Skill | Descrição |
| --- | --- |
| [`branch-diff-report`](branch-diff-report/SKILL.md) | Compara duas branches e gera um relatório de revisão a partir do diff. |
| [`pr-worktree`](pr-worktree/SKILL.md) | Gerencia worktrees Git (bare + worktree por branch) e valida Pull Requests localmente. |

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/carlosdoria/skills/main/install.sh | bash
```

Alternativa clonando o repositório primeiro:

```bash
git clone git@github.com:carlosdoria/skills.git && cd skills && ./install.sh
```

### Instalação manual

Baixe o repositório e copie a pasta de cada skill para `~/.claude/skills/`.

Abra uma nova sessão do Claude Code para que sejam carregadas.

## Estrutura

```text
skills/
├── branch-diff-report/
│   ├── SKILL.md
│   ├── scripts/
│   └── tests/
└── pr-worktree/
    ├── SKILL.md
    ├── scripts/
    └── tests/
```

## Requisitos

- Bash
- Git
- Claude Code

O `gh` (GitHub CLI) é usado pelas skills que precisam consultar PRs no GitHub.

## Melhorias futuras

- [ ] Corrigir `install.sh`, que procura as skills em `skills/*` mas elas estão na raiz do repositório.
- [ ] Adicionar testes automatizados em CI (GitHub Actions) para rodar `tests/run-tests.sh` de cada skill.
- [ ] Documentar processo de contribuição (`CONTRIBUTING.md`) para novas skills.
- [ ] Adicionar versionamento/changelog das skills.
