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

## Testes

Cada skill tem um `tests/run-tests.sh` que usa repositórios temporários e não toca em nada fora deles:

```bash
bash pr-worktree/tests/run-tests.sh
bash branch-diff-report/tests/run-tests.sh
```

## Melhorias conhecidas

- `manage-worktree.sh` ainda não tem testes.
- Registros antigos de `pr-validation`, sem o commit do PR, exigem `--force` no `prepare` e no `cleanup`, e não há teste para esse caso.
