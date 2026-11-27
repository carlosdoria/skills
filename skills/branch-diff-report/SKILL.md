---
name: branch-diff-report
description: Compara duas branches Git e gera um resumo em Markdown para a descrição do PR, com riscos por nível, problemas e melhorias. Somente leitura, em qualquer repositório. Use quando o usuário pedir para comparar duas branches, ver o que uma branch traz em relação à base, resumir, analisar ou revisar um PR ou um diff, ou escrever a descrição de um PR, mesmo sem dizer "relatório" ou "diff".
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/collect-branch-facts.sh *)
---

# Branch Diff Report

Compara duas branches e escreve um resumo em Markdown para a descrição do
PR. Do lado do Git é **somente leitura**: não cria worktree, não muda de
branch, não altera refs nem o working tree. A única escrita possível é a
descrição do PR no GitHub, e só com o OK do usuário (passo 6).

A coleta de dados está no script em `scripts/`. **Nunca reimplemente essa
lógica na mão.** O papel desta skill é o julgamento em volta dele:
interpretar os fatos, separar riscos, problemas e melhorias, escrever o
resumo. Quando outra skill chama esta para o relatório, use `--dir` para
apontar o diretório certo.

## Fluxo

### 1. Descubra as duas branches

- Se o usuário deu as duas, use-as direto.
- Se deu só uma, a outra é a base: tente `gh pr view <branch> --json baseRefName`
  ou use a branch padrão do remoto. Confirme com o usuário se houver dúvida.
- Se deu um número ou link de PR, rode
  `gh pr view <n> --json number,state,baseRefName,headRefName,mergeCommit`.
  PR aberto: compare `baseRefName` com `headRefName`. PR mergeado: compare
  `<mergeCommit>^1` com `<mergeCommit>`, que reproduz o diff do PR mesmo com
  a branch apagada.
- Se descreveu o PR em linguagem natural ("o PR do relatório do capitão"),
  tente `gh pr list` ou `gh search prs --repo <owner/repo> <termos>`.
- Se houver mais de uma candidata, pergunte qual — não adivinhe.

### 2. Colete os fatos

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/collect-branch-facts.sh <base-branch> <feature-branch> [--dir <caminho>] [--no-fetch]
```

`--dir` aponta o repositório ou worktree (padrão: diretório atual);
`--no-fetch` pula a atualização do remoto. Aceita SHA e expressões como
`abc1234^1` no lugar de branch. A comparação parte do **merge-base**, não
da ponta da base, para que commits que entraram na base depois não poluam
o diff.

O script devolve só dados brutos, em seções `=== NOME ===`: metadados,
commits (até 30), totais, arquivos com status e +/- do mais alterado ao
menos (até 50; binários e lockfiles viram uma linha de contagem),
sinalizadores de arquivos sensíveis, diff dos manifestos de dependência,
testes no diff e componentes/hooks com contagem de consumidores. Classificar
risco e escrever o texto é trabalho seu.

Se a saída tiver só o `aviso` de nenhum commit à frente, a branch já entrou
na base. Quando houver `para_comparar`, rode o script de novo com os dois
valores dessa linha, sem perguntar. Sem merge commit (fast-forward), diga
isso ao usuário e peça o intervalo de commits.

Leia também as regras e a spec do projeto, na versão da branch comparada
(`git show <pr_head>:<caminho>`), sem depender do que está em disco:

- **Regras:** o `CLAUDE.md` da raiz já está no seu contexto quando a sessão
  roda dentro do repositório comparado; releia só se ele aparecer em
  `regras_do_projeto` (mudou no diff) ou se `--dir` aponta para outro
  repositório. Leia o `AGENTS.md`, se existir. De `docs/rules/`, liste os
  nomes (`git ls-tree --name-only <pr_head> docs/rules/`) e leia só as
  regras das áreas que o diff toca. Uma violação vira Problema e cita a
  regra.
- **Spec:** `.specs/features/<feature>/spec.md` da feature tocada, ou a
  issue ligada ao PR (`gh pr view <n> --json closingIssuesReferences`).
  Com spec, o resumo ganha a linha `**Spec:**` com os critérios atendidos e
  os pendentes. Num PR parcial, não cobre os critérios de prioridade baixa.

### 3. Interprete

O relatório é um **resumo** para o revisor: o que pode quebrar, o que está
errado e o que vale melhorar. Não é um inventário do diff. As heurísticas
do script são um ponto de partida, não a verdade:

- **Leia o diff dos arquivos que podem render um achado**: os sinalizados
  pelo script, os de lógica com mais linhas alteradas e os que mudam
  contrato (tipos, DTOs, rotas, schemas). Lockfiles, arquivos gerados e
  mudanças só de texto não pedem leitura. Peça os escolhidos numa chamada
  só: `git diff <merge_base> <pr_head> -- <arquivo> <arquivo> ...`. Quando o
  diff não mostra o contexto, aumente-o só naquele arquivo (`-U30`) antes
  de ler o arquivo inteiro.
- **Procure Problemas com estas lentes**, em cada arquivo lido:
  - caso de borda não tratado (null, lista vazia, erro de rede, corrida);
  - estado de erro ou de carregamento faltando;
  - erro tratado na camada errada, longe de onde pode ser resolvido;
  - complexidade além do que a mudança pede.
- **Use a contagem de consumidores** de `=== COMPONENTES ===`: componente
  ou hook com contrato alterado e muitos consumidores pesa mais no risco do
  que um usado em um lugar só.
- **Verifique antes de afirmar.** Um webhook sinalizado como "endpoint
  público" pode já ter validação de assinatura; um arquivo marcado como
  autenticação pode não mexer em credencial. Se o sinal não se confirmou,
  ele não entra no relatório.
- **Só afirme o que você verificou.** Melhor um achado a menos do que um
  achado errado.
- **PR grande (mais de ~30 arquivos):** anote cada achado confirmado num
  arquivo de trabalho no scratchpad assim que confirmá-lo, com seção,
  caminho e texto final. Monte o resumo a partir desse arquivo, para nada
  se perder se o contexto for compactado.

### 4. Classifique os achados

Cada achado vai para exatamente uma seção:

| Seção | O que entra |
|---|---|
| Pontos de atenção | O que pode quebrar em produção ou para quem consome o código, mesmo que o código esteja certo |
| Problemas | Defeito concreto encontrado no diff: bug, caso não tratado, código sem teste, tipo inseguro |
| Melhorias | Sugestão opcional que não bloqueia o merge |

Os achados tratam do código. Mensagem, tipo (`feat`, `fix`, `refactor`)
e organização dos commits não entram em nenhuma seção: os commits servem
só para entender a intenção do PR.

Os pontos de atenção levam um nível de risco:

| Nível | Critério |
|---|---|
| Alto | Migração de banco, mudança em rota pública, autenticação/permissão, remoção de campo ou endpoint, mudança de contrato consumida por terceiros |
| Médio | Mudança de contrato interno, config/env nova, dependência atualizada com major bump, alteração em código compartilhado sem teste |
| Baixo | Mudança de comportamento em fluxo isolado, com teste |

Um problema **bloqueia o merge** quando dá para descrever o cenário
concreto (entrada ou situação → falha) e ele acontece no uso normal:

- bug verificado no fluxo principal (crash, exceção não tratada, tela
  quebrada com dado que existe em produção);
- falha de segurança (segredo no commit, rota sem autenticação, validação
  ou permissão removida, injeção);
- perda ou corrupção de dados (migração destrutiva sem volta, gravação de
  dado errado);
- contrato removido ou renomeado com consumidor fora do PR, confirmado por
  `grep`;
- violação de regra que o projeto marca como obrigatória ("nunca",
  "sempre").

Não bloqueiam: falta de teste (salvo regra do projeto), tipo inseguro sem
cenário de falha, estilo, duplicação e risco hipotético. Na dúvida, não bloqueia: um bloqueio errado tira a confiança
no resumo. Um ponto de atenção Alto também não bloqueia por si só; o
bloqueio exige um defeito confirmado.

### 5. Escreva o resumo

O texto vai para a descrição do PR, lida por quem revisa. Mostre-o na
conversa dentro de um bloco ` ```markdown `, para o usuário copiar sem
perder a formatação. Se o usuário pedir um arquivo, salve como
`PR-REVIEW.md` na raiz do repositório onde a comparação foi feita.

Siga o modelo em `templates/pr-description.md`.

### Regras de formatação

- **Um achado por linha da tabela ou por bullet, em uma ou duas linhas.**
  Diga o que é e onde; não descreva o diff nem explique como o código
  funciona.
- **Pontos de atenção vão de Alto para Baixo.** Se não houver risco Alto ou
  Médio, escreva isso numa linha abaixo da tabela em vez de inflá-la.
- **Problemas são checklist** (`- [ ]`): no GitHub, quem cuida do PR marca
  cada um ao resolver, e a lista de PRs mostra o progresso. Os que
  bloqueiam o merge (passo 4) vêm primeiro, com o prefixo
  `**Bloqueia o merge:**`.
- **Seções vazias são omitidas.** A exceção é Pontos de atenção, que sempre aparece.
  A linha `**Spec:**` só aparece quando há spec (passo 2).
- **Até ~250 palavras no total**, escritas para quem lê o PR sem contexto.
- **No máximo uns 5 itens por seção.** Se houver mais, fique com os mais
  importantes e diga quantos ficaram de fora.
- **Sem seção de "o que mudou", tabela de componentes, cobertura por
  arquivo ou ordem de revisão.** Dependência nova ou com major bump entra
  como risco; arquivo de lógica sem teste entra como problema.
- **Sem título, autor nem contagem de arquivos.** O GitHub já mostra isso
  no PR.
- **Sem ícones.**
- O resumo não é um veredito. Não aprove nem rejeite o PR.

### 6. Publique no PR (opcional)

Depois de mostrar o resumo, ofereça colocá-lo na descrição do PR. Só
publique com o OK explícito do usuário e, antes, leia
`references/publicar-no-pr.md`.

O PR é o único destino. Não cole o diff nem os achados em serviço externo,
gist, pastebin ou Artifact, e não ofereça um link compartilhável do resumo.

Sem o `gh` (GitHub CLI), peça ao usuário as duas branches e não ofereça
publicar.
