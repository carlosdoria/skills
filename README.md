# Claude Code Skills

Coleção de skills e mods para o [Claude Code](https://claude.com/claude-code).
O guia de uso do dia a dia está em [`docs/GUIA-SKILLS.md`](docs/GUIA-SKILLS.md).

## Skills disponíveis

| Skill | Descrição |
| --- | --- |
| [`branch-diff-report`](skills/branch-diff-report/SKILL.md) | Compara duas branches e gera um relatório de revisão a partir do diff. |
| [`plan-and-execute`](skills/plan-and-execute/SKILL.md) | Processo operacional para tarefas não triviais: entender, desenhar com aprovação, planejar, executar e verificar com evidência. |
| [`pr-worktree`](skills/pr-worktree/SKILL.md) | Gerencia worktrees Git (bare + worktree por branch) e valida Pull Requests localmente. |

## Mods disponíveis

| Mod | Descrição |
| --- | --- |
| [`prompt-rewriter`](mods/prompt-rewriter/hooks/register.tsx) | Botão **Prompt** acima da caixa de texto que reescreve o rascunho antes de enviar, com modo Auto e Desfazer. |

## Instalação

O repositório é um plugin do Claude Code chamado `skills`
(`.claude-plugin/plugin.json`). Por isso as skills aparecem com o prefixo do
plugin: `/skills:pr-worktree`, `/skills:branch-diff-report` e
`/skills:plan-and-execute`. Requer Claude Code 2.1.280 ou mais novo.

1. Clone o repositório. No padrão bare + worktree por branch, o plugin é a
   worktree `main`:

   ```bash
   git clone git@github.com:carlosdoria/skills.git
   ```

2. Em `~/.claude/settings.json`, aponte a variável `CLAUDE_CODE_PLUGIN_DIRS`
   para o checkout. Vários caminhos ficam separados por `:`, e o `~` no início
   é aceito:

   ```json
   {
     "env": {
       "CLAUDE_CODE_PLUGIN_DIRS": "~/repos/labs/skills/main:~/repos/labs/skills/main/mods/prompt-rewriter"
     }
   }
   ```

   O primeiro caminho carrega as skills; o segundo, o mod. Cada mod é um
   plugin à parte e precisa do próprio caminho: deixe de fora o que não quiser.

3. Abra uma nova sessão do Claude Code. A variável vale no app desktop, na
   extensão do VS Code e no terminal.

Instalou antes com o antigo `install.sh`? Apague os links que ele criou ao
mesmo tempo em que adiciona a variável, senão cada skill aparece duas vezes:

```bash
rm ~/.claude/skills/branch-diff-report ~/.claude/skills/plan-and-execute ~/.claude/skills/pr-worktree
```

Se instalou via `curl | bash`, apague também o clone em `~/.claude/skills-src`.

### Atualizar

`git pull` no checkout para o qual a variável aponta e uma nova sessão. Skills
novas, alteradas ou removidas acompanham o repositório sem outro passo.

### Testar uma branch antes do merge

Abra o Claude no terminal apontando para a worktree da branch:

```bash
claude --plugin-dir ~/repos/labs/skills/<worktree>
```

A sessão carrega também o plugin da variável, com o mesmo nome, mas as skills
vêm da branch: o `--plugin-dir` prevalece (conferido no Claude Code 2.1.332).
O app desktop e a extensão do VS Code não aceitam essa opção e sempre usam o
checkout da variável.

Para testar o mod de uma branch, aponte para a pasta dele:
`claude --plugin-dir ~/repos/labs/skills/<worktree>/mods/prompt-rewriter`.

## Estrutura

```text
.
├── skills/
│   ├── branch-diff-report/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   ├── scripts/
│   │   ├── templates/
│   │   └── tests/
│   ├── plan-and-execute/
│   │   ├── SKILL.md
│   │   └── tests/
│   └── pr-worktree/
│       ├── SKILL.md
│       ├── references/
│       ├── scripts/
│       └── tests/
├── mods/
│   └── prompt-rewriter/
│       ├── .claude-plugin/plugin.json
│       ├── hooks/
│       ├── tests/
│       └── types/
├── docs/
│   └── GUIA-SKILLS.md  guia de uso
├── .claude-plugin/
│   └── plugin.json     manifesto do plugin de skills
└── .github/workflows/  CI
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

Cada skill tem seus testes em `skills/<skill>/tests/run-tests.sh`, em repositórios
temporários; rode-os depois de alterar os scripts:

- `branch-diff-report`: seções e limites da saída, sinalizadores, branch
  mergeada, somente leitura, sem temporários.
- `pr-worktree`: segurança do prepare/cleanup (repositório comum e layout
  bare) e o `manage-worktree.sh` (`tests/manage-worktree-tests.sh`, que
  também roda sozinho).

Os testes do mod rodam com `claude plugin test mods/prompt-rewriter` e
precisam do Claude Code instalado, por isso ficam fora do CI.

O workflow `.github/workflows/tests.yml` roda tudo em
cada PR e a cada push na `main`, no macOS (Bash 3.2) e no Ubuntu. O job de
`shellcheck` (`-S warning`) também precisa passar.

Para exigir que o PR só entre com os testes verdes, ative em *Settings ›
Branches* uma regra de proteção para `main` com os checks `tests (macos-latest)`,
`tests (ubuntu-latest)` e `shellcheck` como obrigatórios.

## Melhorias futuras

- [ ] Documentar processo de contribuição (`CONTRIBUTING.md`) para novas skills.
- [ ] Adicionar versionamento/changelog das skills.
