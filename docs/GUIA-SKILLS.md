# Guia das minhas skills do Claude Code

Atualizado em 27/11/2026. Cobre as skills e o mod deste repositório (carregados como plugin pela variável `CLAUDE_CODE_PLUGIN_DIRS`), as skills de terceiros em `~/.claude/skills/`, as sincronizadas da conta claude.ai e as embutidas do Claude Code.

## Como uma skill é disparada

Toda skill tem uma `description`. O Claude lê as descrições de todas as skills em toda sessão e decide sozinho carregar uma quando o pedido combina com ela. Nenhuma das minhas skills tem `disable-model-invocation`, então **todas funcionam dos dois jeitos**:

- **Automático:** você pede em linguagem natural ("escreve a descrição do PR") e o Claude carrega a skill certa.
- **Manual:** você digita `/<nome>` (ex.: `/skills:branch-diff-report develop feature/x`). É o jeito garantido: use quando quiser ter certeza de qual skill roda.

O gatilho automático não é exato. Ele depende de o Claude achar que o pedido bate com a descrição. Se uma skill não disparou, chame pelo `/nome`.

Skills de plugin aparecem como `plugin:skill` (ex.: `/anthropic-skills:pdf`). As deste repositório vêm do plugin `skills`: `/skills:branch-diff-report`, `/skills:pr-worktree` e `/skills:plan-and-execute`.

---

## Resumo: situação → skill

| Quero… | Skill | Dispara sozinha? |
|---|---|---|
| Descrição de PR, comparar duas branches, resumir um diff | `skills:branch-diff-report` | Sim |
| Criar/listar/atualizar/remover worktree, clonar repo no padrão bare | `skills:pr-worktree` | Sim |
| Rodar e testar um PR localmente sem tocar na minha branch | `skills:pr-worktree` (e depois `skills:branch-diff-report`) | Sim |
| Planejar e executar uma tarefa não trivial, com aprovação antes de construir | `skills:plan-and-execute` | Sim |
| Reescrever meu prompt antes de enviar | mod `prompt-rewriter` (botão **Prompt**) | Não é skill: ver abaixo |
| Criticar, auditar ou melhorar o visual de uma tela | `impeccable` | Sim (cuidado, ver abaixo) |
| Respostas curtas, economizar tokens | `caveman` | Sim, com "be brief", "less tokens" |
| Achar bugs no diff atual ou num PR | `code-review` | Sim |
| Limpar/simplificar o código alterado (sem caçar bug) | `simplify` | Sim |
| Revisão de segurança da branch | `security-review` | Manual |
| Criar um `CLAUDE.md` para um projeto | `init` | Manual |
| Rodar o app para ver uma mudança funcionando | `run` | Sim |
| Repetir algo de tempos em tempos (ex.: checar deploy a cada 5 min) | `loop` | Sim |
| Menos pedidos de permissão | `fewer-permission-prompts` | Manual |
| Mudar `settings.json`, hooks, permissões, variáveis | `update-config` | Sim |
| PDF, Word, Excel, PowerPoint | `anthropic-skills:pdf` / `docx` / `xlsx` / `pptx` | Sim |
| Criar ou melhorar uma skill | `anthropic-skills:skill-creator` | Sim |

---

## Skills deste repositório (plugin `skills`)

O código fica em `skills/<nome>/` neste repositório. O Claude Code lê direto do checkout para o qual a variável `CLAUDE_CODE_PLUGIN_DIRS` aponta (a worktree `main`): atualizar é dar `git pull`. Para testar uma branch: `claude --plugin-dir ~/repos/labs/skills/<worktree>`.

### `branch-diff-report`
**O que faz:** compara duas branches e escreve um resumo em Markdown para a descrição do PR, em 3 seções: Pontos de atenção (com nível de risco Alto/Médio/Baixo), Problemas (checklist, os que bloqueiam o merge primeiro) e Melhorias. Até cerca de 250 palavras.

**Dispara sozinha quando você pede para:** comparar duas branches, ver o que mudou entre uma branch e outra, resumir ou analisar um PR, escrever a descrição de um PR, gerar relatório ou review de um diff.

**Como usar:**
```
/skills:branch-diff-report develop feature/v3.1.0/adjust-modals
/skills:branch-diff-report 123     # número do PR (precisa do gh)
"escreve a descrição do PR desta branch"
"o que a feature/x traz em relação à develop?"
```
- Com uma branch só, a outra vira a base (via `gh` ou a branch padrão).
- Com um PR já mergeado, compara pelo merge commit.

**O que altera:** nada no Git (só leitura). Faz `git fetch`, a menos que receba `--no-fetch`. Só publica no PR (`gh pr edit`) se você der OK. Se você pedir arquivo, salva `PR-REVIEW.md` na raiz do repo.

**Cuidados:**
- Lê `AGENTS.md`, `CLAUDE.md` e `docs/rules/*.md` da branch comparada: uma regra violada vira Problema.
- Não aprova nem rejeita o PR.
- Código-fonte: `skills/branch-diff-report/`.

### `pr-worktree`
**O que faz:** dois usos.
1. **Worktrees de desenvolvimento** (padrão bare: `<projeto>/.bare` + uma pasta por branch). Comandos `clone`, `bootstrap-bare` (converte um repo existente), `new`, `list`, `update` (só fast-forward) e `remove`.
2. **Validação de PR:** worktree descartável em `../pr-review/pr-<branch>`, com HEAD detached e o diff inteiro aparecendo como alteração não commitada.

**Dispara sozinha quando você pede para:** clonar um repositório, criar, abrir, listar, atualizar ou remover uma worktree, branch ou pasta de trabalho, ou revisar, validar, testar ou rodar um PR localmente e depois limpar.

**Como usar:**
```
"cria uma worktree pra feature/abc saindo da develop"
"abre uma pasta nova pra feature/abc saindo da irop-report"
"lista minhas worktrees"
"valida o PR do relatório do capitão"
"terminei a validação, limpa"
```

**O que altera:** cria e remove worktrees e branches. Nunca commita, faz push, rebase ou apaga branch.

**Cuidados:**
- **Sempre pergunta a pasta** antes de `clone` ou `new`, a menos que você diga "aqui" ou "nesta pasta".
- `bootstrap-bare` reestrutura o projeto e exige que você confirme explicitamente.
- `--force` só depois de mostrar o que será perdido.
- **Ao terminar uma validação de PR, chama `branch-diff-report` sozinha** e entrega o relatório antes de oferecer a limpeza.
- Código-fonte: `skills/pr-worktree/`.

### `plan-and-execute`
**O que faz:** conduz uma tarefa não trivial em fases, do entendimento do pedido à entrega verificada: entender (e perguntar o porquê quando faltar), desenhar com sua aprovação, planejar, executar em passos pequenos e verificar com evidência antes de dizer que terminou. Tarefa trivial vai direto para a verificação.

**Dispara sozinha quando você pede para:** planejar, estruturar, implementar ou executar uma tarefa, feature, correção ou refatoração não trivial, pedir um plano antes do código, pedir para "fazer direito", ou quando o escopo está aberto.

**Como usar:**
```
/skills:plan-and-execute adicionar exportação em CSV no relatório
"planeja antes de mexer: quero trocar a autenticação para OAuth"
```

**Cuidados:**
- Para antes de construir e pede aprovação do desenho e do plano. Em tarefa pequena, isso pode parecer cerimônia: chame a tarefa de trivial ou peça para executar direto.
- Código-fonte: `skills/plan-and-execute/`.

---

## Mod deste repositório: `prompt-rewriter`

**O que faz:** põe uma faixa acima da caixa de texto com três botões:
- **Prompt:** reescreve o rascunho da caixa com o Claude (`sonnet`), mais claro e sem inventar requisitos. Você revisa antes de enviar.
- **Auto:** quando ligado, reescreve cada prompt no envio. Rascunhos com menos de 20 caracteres e comandos com `/` vão como estão. Se a reescrita falhar, o prompt vai como você escreveu. A escolha fica salva entre sessões.
- **Desfazer:** volta ao rascunho de antes da última reescrita pelo botão.

**Onde funciona:** app desktop e CLI no terminal (inclusive dentro do Maestri). Na extensão do VS Code, não conferido.

**Como carrega:** é um plugin à parte, em `mods/prompt-rewriter/`. O caminho dele entra na mesma variável `CLAUDE_CODE_PLUGIN_DIRS`, separado por `:`.

**Cuidados:**
- Cada reescrita é uma chamada ao modelo: no Auto, todo prompt longo custa uma chamada a mais e alguns segundos.
- O que muda o estilo da reescrita é a constante `SYSTEM` em `hooks/register.tsx`; o resto do arquivo decide quando reescrever.
- Testes: `claude plugin test mods/prompt-rewriter`.

---

## Skills de terceiros (instaladas em `~/.claude/skills/`)

### `impeccable` (v4.9.2, instalada em 17/11/2026)
**O que faz:** design de interface, para web e também telas nativas iOS/Android. São 24 subcomandos; os mais úteis:

| Subcomando | Para quê |
|---|---|
| `critique <tela>` | Revisão de UX com nota por critério |
| `audit <tela>` | Acessibilidade, performance, responsividade (tem versão nativa) |
| `harden <tela>` | Estados de erro, i18n, casos de borda |
| `polish <tela>` | Acabamento antes de entregar |
| `layout`, `typeset`, `clarify`, `adapt` | Espaçamento, tipografia, textos, tamanhos de tela |
| `init` / `document` | Criam `PRODUCT.md` / `DESIGN.md` no projeto |

**Dispara sozinha quando você pede para:** desenhar, redesenhar, criticar, auditar, polir ou animar qualquer frontend, componente ou tela. **A descrição é bem ampla:** "melhora o layout dessa tela" provavelmente a ativa.

**Como usar:**
```
/impeccable                         # mostra o menu, não roda nada
/impeccable critique src/application/screens/Home
/impeccable audit ModalWithSteps
```

**O que altera:**
- Na primeira vez em cada sessão, pede para rodar `~/.claude/skills/impeccable/scripts/impeccable context`, que baixa um binário do GitHub (com checksum) para `~/.impeccable/`. Você pode negar: ela segue só com o texto.
- `init` e `document` criam arquivos no repo.

**Cuidados:**
- Tem dois hooks no `~/.claude/settings.json`: um depois de cada Edit/Write (checagem rápida nos arquivos de UI) e outro no fim de cada resposta (checagem completa).
- **Não use** `/impeccable hooks on` (instala hooks no projeto) nem `live` ou `generate` (podem rodar o Claude sem permissões).
- Telemetria e modo `live` estão desligados no `~/.zshrc` (`DO_NOT_TRACK=1`, `IMPECCABLE_LIVE_COPY_AGENT=off`).
- Para desinstalar: `rm -rf ~/.claude/skills/impeccable ~/.impeccable` e apague as 3 linhas do impeccable no fim do `~/.zshrc`.

### `caveman`
**O que faz:** respostas curtas, sem cerimônia, mantendo todo o conteúdo técnico. **Fica ligada até o fim da sessão.**

**Dispara sozinha com:** `/caveman`, "caveman mode", "talk like caveman", "be brief", "less tokens". Pedir "seja breve" pode ligá-la para a sessão inteira.

**Como usar:**
```
/caveman              # liga
/caveman status       # mostra se está ligada
stop caveman          # desliga (ou "normal mode")
```

**Cuidados:**
- `/caveman ultra` e `/caveman wenyan` **não funcionam aqui**: apontam para `ultracave` e `megacave`, que só existem no clone do marketplace (`~/.claude/plugins/marketplaces/caveman/`), não instaladas como skills.
- Texto que fica salvo (código, commits, PRs, docs, memória) continua em prosa normal.
- O próprio README mede só cerca de 3% menos tokens que um simples "responda de forma concisa".

---

## Skills da conta claude.ai (sincronizadas, prefixo `anthropic-skills:`)

Todas disparam sozinhas pelo assunto.

| Skill | Quando |
|---|---|
| `pdf` | Ler, juntar, dividir, preencher, OCR ou criar PDF |
| `docx` | Quando você pede **Word / .docx** explicitamente |
| `xlsx` | Planilha como arquivo (.xlsx, .csv) de entrada ou saída |
| `pptx` | Quando você pede **PowerPoint / .pptx** explicitamente |
| `docs` | Documento editável no claude.ai (padrão para "faz um documento" sem formato) |
| `google-workspace` | Criar ou editar arquivo no Google Docs/Sheets/Slides (precisa do conector autorizado) |
| `skill-creator` | Criar, editar ou testar uma skill |
| `import-memory` | Importar memória exportada de outro assistente |
| `morning` | Só com `/morning` ou "meu morning brief" |

Há um segundo pacote sincronizado em `~/.claude/skills/synced/` com outras skills (`deep-research`, `canvas-design`, `web-artifacts-builder`, `git-worktree-from-base`, `landing-page-*`, ...). Elas **não apareceram** na lista de skills ativas desta sessão; provavelmente vêm de outra conta ou organização.

---

## Skills embutidas do Claude Code (úteis no dia a dia)

| Skill | Dispara sozinha? | Uso |
|---|---|---|
| `code-review` | Sim | `/code-review medium` (diff atual) · `/code-review high 123` (PR) · `--fix` aplica as correções · `--comment` posta no PR. Níveis: low → max (`max` só se você pedir; é caro) |
| `simplify` | Sim | Reaproveitamento, simplificação, eficiência no código alterado, e aplica as mudanças. Não caça bug |
| `security-review` | Manual | `/security-review`: revisão de segurança das mudanças da branch |
| `init` | Manual | `/init`: cria `CLAUDE.md` do projeto |
| `run` | Sim | "roda o app e mostra funcionando" |
| `loop` | Sim | `/loop 5m <comando>`: repete em intervalo. Não serve para tarefa única |
| `fewer-permission-prompts` | Manual | Lê seu histórico e sugere comandos para liberar no `.claude/settings.json` |
| `update-config` | Sim | "sempre que X faça Y", permissões, variáveis, hooks |
| `keybindings-help` | Sim | Atalhos de teclado |
| `claude-api` | Sim | Quando o código usa a API/SDK da Anthropic |
| `dataviz` | Sim | Qualquer gráfico ou dashboard |

---

## O que roda sozinho e não é skill

- **Hooks do `impeccable`** em `~/.claude/settings.json` (ver acima).
- **Mod `prompt-rewriter`:** reescreve o prompt no envio quando o Auto está ligado.
- **Padrões pessoais:** `~/.claude/CLAUDE.md` importa `claude/CLAUDE.md` deste repositório e vale em toda sessão, em qualquer projeto.
- **Memória por projeto** em `~/.claude/projects/<projeto>/memory/`: carregada automaticamente em toda sessão daquele projeto.

## Dicas
- **Quer garantia?** Use `/nome`. O gatilho automático pode errar para os dois lados.
- **Uma skill disparou sem você querer?** Diga "não use a skill X" ou interrompa.
- **Duas skills parecidas?** Fale o nome: "usa a skills:pr-worktree, não a git-worktree".
