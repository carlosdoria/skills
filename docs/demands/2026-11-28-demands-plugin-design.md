# Plugin de demandas: desenho da V1

- Data: 2026-11-28
- Situação: aprovado em 2026-11-28
- Destino: `carlosdoria/skills` (público), em `mods/demands/`. Plano de implementação: `docs/demands/2026-11-28-demands-plugin-v1-plan.md`.
- Base: [affaan-m/ECC](https://github.com/affaan-m/ECC), MIT, commit `4adeee6` (o mais recente em 2026-11-28).

## Por que

Você quer que os agentes do Claude Code só mudem um projeto a partir de uma
demanda registrada, com o plano pronto antes de qualquer alteração, e que você
aprove cada passo até confiar no agente e ligar o modo automático.

A V1 é deliberadamente simples: as demandas ficam em arquivos dentro de cada
projeto, versionados no git junto com o código. Ela serve para ver o plugin
funcionando na prática e decidir, com dados, se a estrutura continua por
projeto ou se passa a existir um perfil central (ver "Candidatos para a V2").

## Objetivos

- Ciclo **Criada → Planejada → To-do → Fazendo → Concluída**, movido só pelo plugin.
- Travas: sem demanda ativa, o agente (subagentes incluídos) não edita arquivos, não roda comandos que gravam e não faz commit nem push.
- Aprovação em cada transição, com a opção `autoApprove` para o modo automático.
- Agente planejador com estrutura fixa; o plano termina com o prompt que fará a alteração.
- Perguntas no chat da sessão, com notificação do Mac.
- Dashboard em localhost, só para visualizar, atualizado ao vivo.
- Plugin igual nos dois Macs via `git pull` do `skills`; demandas iguais via `git pull` de cada projeto.
- Nada sensível no repositório público.

## Fora do escopo da V1

- Firestore, Firebase, login e perfis.
- Sincronização além do git, e tratamento de conflitos entre máquinas ou pessoas (resolvidos à mão, como qualquer conflito de merge).
- Dashboard central com vários projetos.
- Agente rodando sem sessão aberta.
- Responder perguntas pelo dashboard.
- Travar você: suas edições manuais continuam livres.
- Integração com GitHub Issues, Jira ou Linear.

## O que faria isso falhar, mesmo funcionando

- A trava atrapalhar projetos que não usam o plugin, como os repositórios de trabalho.
- O agente conseguir se autoaprovar ou desligar a trava editando a configuração ou o próprio plugin.
- Dados de projeto ou de cliente irem parar no repositório público `skills`.
- A V1 nascer presa aos arquivos, a ponto de a V2 exigir reescrever travas, ferramentas e dashboard.

## Restrições

- Carregado por `CLAUDE_CODE_PLUGIN_DIRS` no `~/.claude/settings.json` de cada Mac, como o resto do `skills`. Atualizar: `git pull` e nova sessão.
- Formato mod do Claude Code (conferido na versão 2.1.331): `hooks/register.tsx` com a API `$`. O módulo não tem Node; o servidor do dashboard é um processo à parte.
- Só age em projetos que tenham `demands/config.json`. Nos outros, não faz nada.

## Caminhos considerados

| Decisão | Opções | Escolhido |
|---|---|---|
| Onde mora o plugin | Arquivos soltos no `.claude/` de cada projeto · repositório próprio · lib npm · mod no `skills` | **Mod no `skills`**: aproveita o clone e a variável que já existem nos dois Macs |
| Como travar | Hooks de shell no `settings.json` · mod | **Mod**: nega a chamada dentro do Claude Code, pede aprovação num diálogo que o agente não responde e notifica pelo canal nativo |
| Ferramentas do agente | Servidor MCP separado · `$.tool.register` | **`$.tool.register`**: sem processo extra |
| Onde ficam as demandas | Firestore com cópia local · branch própria no git · só local · **arquivos no git do projeto** | **Arquivos no git do projeto** na V1: nada para configurar e funciona offline. O Firestore fica como candidato para a V2 |

## Desenho

### Nomes

Todo nome fica em inglês: arquivos, pastas, branches, funções, campos, valores
de estado, ferramentas, comandos e títulos das seções do arquivo de demanda.
O que é lido por pessoas fica em português: mensagens, perguntas de aprovação,
rótulos do dashboard e documentação.

| Estado (no arquivo) | Rótulo para você |
|---|---|
| `created` | Criada |
| `planned` | Planejada |
| `todo` | To-do |
| `doing` | Fazendo |
| `done` | Concluída |

### Onde fica cada coisa

No plugin (público, sem dado de projeto):

```text
mods/demands/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── hooks/register.tsx        travas, ferramentas, comandos e avisos
├── lib/states.ts            ciclo de estados e validação do plano
├── lib/storage.ts      única port de leitura e gravação das demands
├── lib/demand.ts            formato do file (cabeçalho e seções)
├── lib/shell-readonly.ts      reconhece comandos só de leitura (adaptado do ECC)
├── lib/sensitive.ts           detector de segredos e terms proibidos
├── agents/planner.md
├── templates/execution-prompt.md
├── dashboard/server.mjs      Node 18+, sem dependências npm
├── dashboard/public/         index.html, app.js, styles.css, vendor/
└── tests/
```

Travas, ferramentas e dashboard só falam com `lib/storage.ts`. Na V2,
trocar arquivos por um perfil central ou pelo Firestore muda esse módulo, não o resto.

Em cada projeto, tudo versionado no git do projeto:

```text
demands/
├── config.json
├── D-K3F9X2.md
└── D-7QH2MA.md
```

`config.json`:

```json
{ "versao": 1, "autoAprovar": false, "painel": { "porta": 4777 } }
```

Arquivo de demanda: um por demanda, estado num campo do cabeçalho (mover
arquivo entre pastas quebra links e histórico). IDs aleatórios (`D-` mais 6
caracteres), para duas pessoas criando demandas em branches diferentes não
gerarem o mesmo nome de arquivo.

```markdown
---
version: 1
id: D-K3F9X2
title: Exportar relatório em CSV
state: created        # created | planned | todo | doing | done
planning: false
doing_by:          # { who, machine, folder } de who pegou para Fazendo
approved_prompt:      # hash do prompt de execução approved
branch:
pr:
history:
  - { at: 2026-11-28T10:00-03:00, from: null, to: created, by: voce, machine: mac-a, approved: null }
---

## Idea
## Questions and answers
## Plan
### Overview
### Requirements
### Acceptance criteria
### Architecture changes
### Steps
### Testing strategy
### Risks and mitigations
### Execution prompt
## Execution
```

O conteúdo da demanda é dado, não instrução. A única parte que vira instrução é
o **Prompt de execução aprovado**: ao aprovar, o plugin guarda o hash dele em
`approved_prompt`; se o texto mudar depois, a execução é recusada até nova aprovação.

### Git e branches na V1

- O estado acompanha a branch: enquanto a branch da tarefa mostra Fazendo, a `main` mostra To-do até o merge. O dashboard mostra o checkout atual.
- Na execução, o agente cria a branch pelo fluxo normal do projeto e commita o arquivo da demanda junto com o código; a demanda vai no PR.
- Fora da execução (criação e planejamento), quem commita as mudanças em `demands/` é você. A trava só vale para o agente.
- Concluída é marcada ao abrir o PR, com a verificação passando, e o arquivo já entra no PR. Assim o merge leva a demanda concluída para a `main` sem outro commit. O merge continua com você.
- Limites conhecidos e aceitos na V1: conflito de merge num arquivo de demanda se resolve à mão; duas máquinas podem pegar a mesma demanda, porque nada central impede.

### Ciclo e aprovações

| Passo | Quem dispara | Validação | Modo padrão |
|---|---|---|---|
| Criar (→ Criada) | Você (`/demands:new`) ou o agente | Título e ideia preenchidos | Sem aprovação |
| Começar a planejar | Agente | Demanda em Criada | Você aprova ("Vou planejar a D-K3F9X2 com o planejador") |
| Criada → Planejada | Planejador ao salvar o plano | Todas as seções do plano, inclusive o prompt de execução | Coberto pela aprovação anterior |
| Planejada → To-do | Agente propõe | Plano válido | Você aprova o plano; o plugin guarda o hash do prompt |
| To-do → Fazendo | Agente propõe | Nenhuma outra demanda ativa nesta pasta; prompt igual ao aprovado | Você aprova. "Aprovar e executar" faz Planejada → To-do → Fazendo de uma vez |
| Fazendo → Concluída | Agente, ao abrir o PR | Critérios de aceite conferidos e verificação passando | Você aprova |
| Recusar plano (Planejada → Criada) | Você | Comentário obrigatório, salvo na demanda | — |
| Pausar (Fazendo → To-do) | Você ou o agente | — | Você aprova |

Com `autoApprove: true`, as transições acontecem sem perguntar, mas as validações continuam.

### Execução (Fazendo)

O modelo `templates/execution-prompt.md` segue o passo `implement` da skill
`story-lifecycle` e a skill `verification-loop` do ECC, sem exigir o ECC instalado:

1. Ler as convenções do projeto (`CLAUDE.md`, `AGENTS.md`, regras instaladas).
2. Criar a branch pelo fluxo do projeto.
3. Testes primeiro, a partir dos critérios de aceite.
4. Implementar até os testes passarem.
5. Revisão com o revisor da linguagem, se existir no projeto (ex.: `typescript-reviewer`); senão, com o agente `skills:revisor`, se estiver instalado; senão, uma revisão própria em contexto limpo.
6. Verificação: build, tipos, lint, testes, busca de segredos e revisão do diff.
7. Conferir cada critério de aceite.
8. Commitar código e demanda, abrir o PR e chamar `complete`.

### Travas

Valem quando o projeto tem `demands/config.json`, no agente principal e nos
subagentes (o evento `tool.call` cobre todos). Leem os arquivos do checkout
atual e funcionam offline. Se a trava falhar, ela nega.

"Demanda ativa" quer dizer: em Fazendo, com `doing_by` igual a esta máquina e a esta pasta.

| Situação | O agente tenta | Resultado |
|---|---|---|
| Sem demanda ativa | Editar ou criar arquivo (Edit, Write, MultiEdit, NotebookEdit) | Negado, com a instrução: "crie ou inicie uma demanda: `/demands:next`" |
| Sem demanda ativa | Comando de terminal | Só passa se for de leitura (`ls`, `cat`, `grep`, `git status`, `git diff`...) |
| Sem demanda ativa | `git commit` ou `git push` | Negado |
| Sempre | Gravar em `demands/` por editor ou terminal | Negado: só pelas ferramentas do plugin |
| Sempre | Mudar `demands/config.json` | Negado: só você edita |
| Sempre | Mexer na pasta do plugin ou no `~/.claude/settings.json` | Negado em projetos com demandas |
| Com demanda ativa | Editar, rodar comandos, commitar e fazer push | Liberado; as permissões normais do Claude Code continuam valendo |

Quem fizer `git pull` e encontrar uma demanda em Fazendo por outra pessoa ou
máquina continua com a trava fechada para ela.

### Ferramentas que o plugin dá ao agente

Registradas com `$.tool.register`; o agente as vê como `mcp__demands__<name>`.

| Ferramenta | O que faz |
|---|---|
| `list` | Lista demandas e estados |
| `create` | Cria uma demanda em Criada |
| `plan` | Pede aprovação e marca `planning: true` |
| `ask` | Notifica o Mac, pergunta no chat e grava pergunta e resposta na demanda |
| `save_plan` | Valida as seções e move para Planejada |
| `execute` | Pede aprovação do plano e da execução, guarda o hash do prompt e move para To-do e Fazendo |
| `complete` | Recebe o link do PR, pede aprovação e move para Concluída |
| `pause` | Volta de Fazendo para To-do |

Toda ferramenta que muda estado: valida, notifica e pergunta (modo padrão),
grava pelo `lib/storage.ts` e acrescenta uma linha ao `history`. A
resposta vem do diálogo em que você clica (`$.ui.ask`), que o agente não
consegue responder sozinho.

### Comandos

- `/demands:init`: cria `demands/config.json` no projeto atual (liga o plugin ali), depois de confirmar com você.
- `/demands:new <idea>`: cria uma demanda.
- `/demands:next`: o agente pega a próxima. Executa primeiro o que está em To-do; se não houver, planeja a mais antiga em Criada.
- `/demands:status`: resumo no chat, com o link do dashboard.
- `/demands:dashboard`: sobe o dashboard e abre o navegador.

### Agente planejador

`agents/planner.md`, tipo `demands:planner`. Só lê o projeto (Read,
Grep, Glob, terminal de leitura) e usa `ask` e `save_plan`.

As seções do plano vêm do formato do agente `planner` do ECC (visão geral,
requisitos, mudanças de arquitetura, passos por fase, estratégia de testes,
riscos e mitigação). Os critérios de sucesso do `planner` viram os critérios de
aceite testáveis da skill `story-lifecycle`. O plano termina com o **Prompt de execução**, preenchido a
partir de `templates/execution-prompt.md`: objetivo, contexto e arquivos, passos,
critérios de aceite, como verificar, o que não fazer e a entrega (branch,
commits, PR). `save_plan` recusa o plano se faltar alguma parte. No modo
automático, o planejador só pergunta quando não há um padrão razoável para seguir.

### Perguntas e avisos

- `ask` chama `$.ui.notify` (notificação nativa do Mac, pelo canal que você usa) e `$.ui.ask` (pergunta no chat).
- Pedidos de aprovação também notificam.
- Perguntas e respostas ficam na seção "Perguntas e respostas" da demanda.

### Dashboard

- `dashboard/server.mjs`, Node 18+, sem dependências npm, ouvindo só em `127.0.0.1`, na porta do `config.json`.
- Lê `demands/*.md` do checkout atual, observa a pasta e envia cada mudança para a página por Server-Sent Events. A página se reconecta sozinha.
- Tela: quadro com as 5 colunas; selos "aguardando você", "planejando" e "modo automático"; detalhe do card com plano, histórico e link do PR; linha do tempo dos eventos; a branch atual no topo.
- Bibliotecas: Shoelace (componentes), Alpine.js (reatividade) e marked (mostrar o plano em Markdown), com versões fixas, guardadas em `dashboard/public/vendor/`. A página funciona sem internet e não chama nenhum CDN.
- Um servidor por projeto.

### Travas contra informação sensível no repositório público

1. `.gitignore` na raiz do `skills` com `.impeccable/`, `.env*`, `node_modules/` e arquivos de execução. Pastas locais de ferramentas de trabalho não entram nele, porque o próprio nome já identificaria a empresa: ficam no ignore global de cada Mac (`~/.config/git/ignore`), e a lista de termos proibidos (item 4) barra um commit que escape.
2. CI: job gitleaks em todo PR e em todo push na `main`, marcado como check obrigatório na proteção da `main`.
3. Pre-commit local em `.githooks/pre-commit`, que roda o detector do plugin (`lib/sensitive`) nos arquivos staged. Liga-se uma vez por Mac com `git config core.hooksPath .githooks`. Não exige instalar nada além do Node.
4. Termos proibidos (nomes de clientes, empresas, domínios internos) ficam fora do repositório, em `~/.config/skills/forbidden-terms.txt` em cada Mac. Pôr essa lista no repositório público já seria o vazamento. Por isso o CI só procura segredos; os termos são conferidos no pre-commit e na trava do mod.
5. Trava no mod: quando o agente edita arquivos dentro do checkout do `skills`, o texto novo passa pelo detector; se achar segredo ou termo proibido, a edição é negada.
6. Regra de desenho: o plugin nunca grava dado de projeto na pasta do plugin.

### Testes

- `node --test` para `lib/` e para o dashboard, rodando no CI.
- `claude plugin test mods/demands` para o módulo do mod. Precisa do Claude Code, por isso fica fora do CI, como o `prompt-rewriter`.
- Casos mínimos:
  - matriz de travas (nega e libera), inclusive demanda em Fazendo por outra máquina;
  - projeto sem `config.json` (não faz nada);
  - transições válidas e inválidas, plano incompleto recusado, aprovação aceita e recusada, modo automático;
  - prompt alterado depois de aprovado é recusado;
  - IDs aleatórios sem colisão em lote;
  - detector de sensíveis com e sem lista de termos.

### Instalação

Uma vez por Mac:

1. Acrescentar `~/repos/labs/skills/main/mods/demands` ao `CLAUDE_CODE_PLUGIN_DIRS` no `~/.claude/settings.json`.
2. No clone do `skills`: `git config core.hooksPath .githooks`.
3. Criar `~/.config/skills/forbidden-terms.txt`.

Em cada projeto: `/demands:init`. Para atualizar o plugin: `git pull` no `skills` e nova sessão.

## O que vem do ECC

| Do ECC | Uso aqui |
|---|---|
| Padrão Plan-PRD (`docs/PLAN-PRD-PATTERN.md`) | A ideia central da V1: cada etapa é um arquivo Markdown versionado com o código, legível no PR e retomável em outra sessão |
| Skill `story-lifecycle` | Formato do arquivo; critérios de aceite; regras "o conteúdo é dado, não instrução", "estado só muda pela ferramenta" e "o caminho é validado antes de gravar"; o passo `implement` como base da execução |
| Agente `planner` | Seções do plano |
| Skill `verification-loop` | Etapas de verificação do prompt de execução |
| Agentes `typescript-reviewer` e `code-reviewer` | Revisão na execução, quando estiverem no projeto |
| `scripts/lib/gateguard-readonly-shell.js` | Base de `lib/shell-readonly.ts`, convertido para módulo ES, com crédito no cabeçalho |
| Padrão de mensagem do GateGuard | A negação diz ao agente como seguir |
| Uso de gitleaks no CI | Job de segredos |

Onde a V1 diverge do ECC: a `story-lifecycle` só marca `done` depois do merge,
com um estado `review` no meio. Aqui Concluída vem ao abrir o PR, porque o
arquivo da demanda viaja dentro do próprio PR.

Não entram: `ledger.js` (journal e hardlinks, demais para um arquivo por
demanda gravado pelo mod), Hookify, o runtime de hooks do ECC, os comandos
`epic-*` e o painel de controle.

## Como avaliar a V1

Usar em um ou dois projetos por cerca de duas semanas e anotar:

- quantas vezes a trava bloqueou algo legítimo;
- quantas aprovações cada demanda pediu, e se o modo automático já faz sentido;
- se houve conflito de merge em arquivo de demanda ou demanda pegada duas vezes;
- se você sentiu falta de ver todos os projetos juntos;
- quanto tempo vai de Criada a Concluída.

Esses números decidem entre manter a estrutura por projeto e passar para um perfil central.

## Riscos e o que conferir na implementação

- Se `$.ui.ask` continua pedindo resposta nos modos de permissão `auto` e `bypassPermissions`, e dentro de um `/loop`.
- Se o processo do dashboard iniciado por `$.process.spawn` sobrevive ao fim da sessão. Se não, o comando passa a mostrar a linha `node .../server.mjs` para você rodar num terminal.
- Ferramentas de terceiros que gravam arquivos (MCPs) ficam fora da trava na V1.
- O reconhecimento de comandos só de leitura é conservador e pode negar comandos legítimos. A mensagem de negação precisa ser clara, e a lista, fácil de ampliar.
- Se o projeto for público, as demandas (ideias, perguntas, planos) também ficam públicas.

## Candidatos para a V2

O que já foi pensado, para não começar do zero:

- **Firestore com cópia local:** a cópia em `demands/` continua sendo a fonte das travas; uma fila em `demands/.sync/` envia as alterações quando há internet, com a condição de versão do Firestore. Já decidido para esse caso: em conflito, a demanda pausa e pergunta a você; offline, o agente pode começar a executar.
- **Perfis:** cada projeto aponta para um perfil (Firebase e login), o que permite um Firebase por projeto onde o isolamento importa. Login feito por você no terminal, token no Keychain.
- **Dashboard central:** uma lista de projetos por Mac, preenchida pelo `/demands:init`, e uma tela com seletor de projeto, ainda lendo as cópias locais.
- **Executor online no estilo Hermes:** uma máquina sempre ligada que pega e executa demandas sem sessão aberta, com aprovações e perguntas pelo dashboard ou pelo Telegram.
- **Agrupar repositórios:** vários repositórios com o mesmo `projetoId` e um campo `repositorio` em cada demanda.

## Decisões suas

- Plugin como mod no `carlosdoria/skills`, público, com travas contra informação sensível.
- V1 com demandas em arquivos versionados no git de cada projeto, sem Firestore, sem login e sem tratar conflitos.
- Nomes sempre em inglês; nenhum nome de empresa ou cliente no repositório público.
- Alerta: pergunta no chat da sessão e notificação do Mac.
- To-do quando você aprova o plano.

## Decisões minhas para você conferir

- IDs aleatórios (`D-K3F9X2`).
- `doing_by` com quem, máquina e pasta.
- Hash do prompt aprovado, com recusa se o texto mudar.
- Leitura e gravação isoladas em `lib/storage.ts`.
- Criada → Planejada sem nova aprovação: a aprovação para começar a planejar cobre.
- Voltas permitidas: recusar plano (→ Criada) e pausar (→ To-do).
- Concluída ao abrir o PR com a verificação passando.
- O agente commita a demanda junto com o código na execução; fora dela, quem commita é você.
- O agente pode criar demandas sem aprovação.
- Bibliotecas do dashboard: Shoelace, Alpine.js e marked, guardadas no repositório.
- Pre-commit com o detector próprio, sem instalar gitleaks localmente.
