# Claude Code Skills

Coleção de skills e mods para o [Claude Code](https://claude.com/claude-code).
O guia de uso do dia a dia está em [`docs/GUIA-SKILLS.md`](docs/GUIA-SKILLS.md).

## Skills disponíveis

| Skill | Descrição |
| --- | --- |
| [`branch-diff-report`](skills/branch-diff-report/SKILL.md) | Compara duas branches e gera um relatório de revisão a partir do diff. |
| [`plan-and-execute`](skills/plan-and-execute/SKILL.md) | Processo operacional para tarefas não triviais: entender, desenhar com aprovação, planejar, executar e verificar com evidência. |
| [`pr-worktree`](skills/pr-worktree/SKILL.md) | Gerencia worktrees Git (bare + worktree por branch) e valida Pull Requests localmente. |

## Outros componentes do plugin

| Componente | Descrição |
| --- | --- |
| [`agents/revisor.md`](agents/revisor.md) | Subagent `skills:revisor`: revisa um diff ou uma branch em contexto limpo, somente leitura, e aponta bugs e riscos com arquivo e linha. |
| [`hooks/confirmar-comandos.sh`](hooks/confirmar-comandos.sh) | Hook `PreToolUse` no Bash que exige confirmação explícita antes de `git push --force`, push na `main`/`master`, `git reset --hard`, `git clean -f`, `git branch -D` e `rm -rf`, mesmo com o comando liberado por regra ou no modo auto. |
| [`statusline/statusline.sh`](statusline/statusline.sh) | Statusline com pasta (branch), modelo, contexto usado e custo da sessão. Não faz parte do plugin: é configurada no `settings.json` (ver abaixo). |

As skills `branch-diff-report` e `pr-worktree` pré-aprovam os próprios
scripts com `allowed-tools`. Na `pr-worktree`, só `list` e `update` rodam
sem pedir permissão.

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

### Padrões pessoais (`CLAUDE.md`)

[`claude/CLAUDE.md`](claude/CLAUDE.md) guarda instruções que valem em todos os
projetos, em todas as máquinas. O `~/.claude/CLAUDE.md` de cada máquina só
importa esse arquivo, com uma linha:

```text
@~/repos/labs/skills/main/claude/CLAUDE.md
```

Para criar:

```bash
echo '@~/repos/labs/skills/main/claude/CLAUDE.md' > ~/.claude/CLAUDE.md
```

Se o `~/.claude/CLAUDE.md` já existir, acrescente a linha em vez de
sobrescrever. O que valer só para uma máquina pode ficar abaixo dela, fora do
repositório. Lembre que este repositório é público: nada de cliente ou empresa
nesse arquivo.

### Statusline

Precisa do `jq` (já vem no macOS 15 ou mais novo). Em `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/repos/labs/skills/main/statusline/statusline.sh"
  }
}
```

Ela roda localmente e não gasta tokens. Aparece na CLI, inclusive no
Maestri. No app desktop e na extensão do VS Code, não conferido.

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
├── agents/
│   └── revisor.md      subagent skills:revisor
├── hooks/
│   ├── hooks.json      hooks do plugin de skills
│   ├── confirmar-comandos.sh
│   └── tests/
├── statusline/
│   └── statusline.sh
├── mods/
│   └── prompt-rewriter/
│       ├── .claude-plugin/plugin.json
│       ├── hooks/
│       ├── tests/
│       └── types/
├── docs/
│   └── GUIA-SKILLS.md  guia de uso
├── claude/
│   └── CLAUDE.md       padrões pessoais, importados pelo ~/.claude/CLAUDE.md
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

O hook de confirmação tem os seus em `hooks/tests/run-tests.sh`: o que ele
pega e o que deixa passar.

Os testes do mod rodam com `claude plugin test mods/prompt-rewriter` e
precisam do Claude Code instalado, por isso ficam fora do CI.

O workflow `.github/workflows/tests.yml` roda tudo em cada PR e a cada push na
`main`, no macOS (Bash 3.2) e no Ubuntu. O job de `shellcheck` (`-S warning`)
também precisa passar, e o job `plugins` instala o Claude Code e roda
`claude plugin validate` nos dois plugins.

Para exigir que o PR só entre com os testes verdes, ative em *Settings ›
Branches* uma regra de proteção para `main` com os checks `tests (macos-latest)`,
`tests (ubuntu-latest)`, `shellcheck` e `plugins` como obrigatórios.

## Melhorias futuras

- [ ] Documentar processo de contribuição (`CONTRIBUTING.md`) para novas skills.
- [ ] Adicionar versionamento/changelog das skills.
