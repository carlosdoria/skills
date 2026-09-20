# skills

Skills do Claude Code para trabalhar com branches, PRs e worktrees Git.

## Skills

| Skill | O que faz |
|---|---|
| [branch-diff-report](branch-diff-report/SKILL.md) | Compara duas branches e gera um relatório de revisão em Markdown: o que mudou, áreas afetadas, pontos de atenção por risco, arquivos sem teste e ordem sugerida de revisão. Somente leitura. |
| [pr-worktree](pr-worktree/SKILL.md) | Cria, lista, atualiza e remove worktrees Git, e prepara worktrees descartáveis para revisar e testar um PR sem tocar na sua branch. Delega o relatório escrito para `branch-diff-report`. |

## Instalação

Copie as pastas das skills para o diretório de skills do usuário:

```bash
cp -R branch-diff-report pr-worktree ~/.claude/skills/
```

Abra uma sessão nova do Claude Code para que as skills sejam carregadas.

Requisitos: `git`. O `gh` (GitHub CLI) é opcional e serve para descobrir a base de um PR.

## Melhorias conhecidas

- `prepare-pr-validation.sh` e `cleanup-pr-validation.sh` ainda usam `git worktree remove --force` internamente. Falta confirmar que a checagem de edições locais cobre todos os casos antes desse comando.
- Os testes em `tests/run-tests.sh` de cada skill ainda não foram executados nem revisados quanto à cobertura de `manage-worktree.sh`.
- Os scripts não têm permissão de execução; funcionam porque as skills os chamam com `bash scripts/...`.
