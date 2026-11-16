---
name: plan-and-execute
description: Conduz o agente pelo ciclo completo de uma tarefa não trivial, do entendimento do pedido à entrega verificada, com pontos de aprovação do usuário antes de construir. Use sempre que o usuário pedir para planejar, estruturar, implementar ou executar uma tarefa, feature, correção ou refatoração não trivial, pedir um plano antes do código, pedir para "fazer direito" ou reclamar que o agente saiu codando sem entender, ou iniciar um trabalho cujo escopo esteja aberto — mesmo que não use as palavras planejar, plano ou processo.
---

# Plan and Execute

Instrução prescritiva para agentes. Siga as fases em ordem. Cada fase tem um
critério de saída — não avance sem cumpri-lo.

**Quando não usar:** tarefa trivial, em que tudo que importa está no pedido
(ex.: "troque a cor do botão para azul"). Execute direto, diga o que fez e
aplique apenas as Fases 6 e 7 (verificar e entregar).

## Princípios

1. **Entenda antes de agir.** Nenhuma linha de código, arquivo ou configuração
   antes de saber o que o usuário quer e por quê.
2. **Evidência antes de afirmação.** Nunca declare algo pronto, corrigido ou
   passando sem ter rodado a verificação e lido a saída.
3. **O usuário aprova o "quê" antes do "como".** Design aprovado → plano →
   execução. Nunca o contrário.
4. **Mudanças pequenas e verificáveis.** Cada etapa deve poder ser testada
   isoladamente e revertida sem dor.
5. **Reuse antes de criar.** O projeto provavelmente já resolve parte do
   problema. Procure antes de escrever.
6. **Reporte com honestidade.** Teste falhou? Diga, com a saída. Etapa pulada?
   Diga qual e por quê.

## Fase 1 — Entender o pedido

**Objetivo:** saber o que o usuário quer e por quê, antes de qualquer ação.

1. Classifique o pedido: trivial → execute direto (ver "Quando não usar");
   não trivial → continue nesta fase.
2. Descubra o **porquê**. Se o usuário não disse, pergunte com uma questão
   aberta, nos termos dele, sem oferecer opções. O porquê decide as cem
   decisões pequenas que ele nunca vai mencionar.
3. Pergunte **apenas** quando a resposta mudaria o que será construído. Caso
   contrário, declare sua escolha com a justificativa, como proposta
   corrigível, e siga.
4. Faça **uma pergunta por vez**. Quando as opções forem nomeáveis, descreva
   cada uma concretamente, com trade-offs, e indique qual você escolheria.
5. Defaults silenciosos são proibidos: todo default que você assumir deve ser
   dito em voz alta. Um default que o usuário nunca ouviu é um default que
   ele não pôde rejeitar.

**Saída da fase:** você consegue explicar o pedido com suas próprias
palavras — o quê, para quem e por quê — e o usuário confirmou.

## Fase 2 — Explorar o contexto

**Objetivo:** conhecer o terreno antes de propor qualquer coisa.

1. Leia tudo que o usuário referenciou (specs, arquivos, conversas
   anteriores) e o código/material que isso conecta.
2. Continue lendo até conseguir explicar **como as partes relevantes
   funcionam hoje** e **o que a mudança tocaria**.
3. Procure ativamente funções, utilitários e padrões existentes que possam
   ser reusados. Não proponha código novo quando já existe implementação
   adequada.
4. **Nunca pergunte o que o projeto já responde.** Nunca reabra o que o
   usuário já decidiu.
5. Se encontrar algo que o usuário talvez não tenha considerado — uma
   restrição, um conflito, um caminho mais barato — diga claramente antes
   de prosseguir.

**Saída da fase:** mapa mental do estado atual + lista do que pode ser
reusado + impactos da mudança.

## Fase 3 — Desenhar a abordagem

**Objetivo:** escolher, com o usuário, COMO construir.

1. Gere 2–3 alternativas **reais** de implementação. Descarte as fracas: as
   que trabalham contra o porquê do usuário e as que o projeto existente
   inviabiliza.
2. Apresente as restantes em uma mensagem própria: cada uma concreta o
   bastante para visualizar, com trade-offs, ancorada no que o projeto
   realmente faz.
3. Recomende uma e justifique. Peça que o usuário escolha. Se ele delegou o
   "como", anuncie que seguirá com a sua recomendação.
4. Quando houver genuinamente um único caminho sensato, diga isso e explique
   por que os outros não servem.
5. Escreva o design (curto para mudança pequena; completo para projeto):
   intenção e porquê, objetivos, não-objetivos, anti-objetivos, restrições,
   abordagens consideradas e escolhida, decisões já tomadas, o que fica a
   cargo do executor.

**🚫 HARD GATE:** nada é construído — nenhum código, scaffold, dependência
instalada — até o usuário aprovar o design. Ler e explorar é permitido;
construir não.

**Saída da fase:** design aprovado pelo usuário.

## Fase 4 — Planejar

**Objetivo:** transformar o design em etapas executáveis.

1. Escreva um plano com **etapas pequenas, ordenadas e independentes quando
   possível**.
2. Cada etapa declara: o que muda, em quais arquivos (nomeie os críticos), e
   o **critério de pronto** (comando a rodar, saída esperada).
3. Referencie as funções e utilitários existentes que serão reusados, com
   caminho do arquivo.
4. Inclua uma seção de **verificação fim-a-fim**: como provar que o conjunto
   funciona (rodar a aplicação, testes, inspeção manual).
5. Para padrões repetidos em muitos arquivos, descreva o padrão uma vez e
   liste caminhos representativos — não enumere tudo.

**Saída da fase:** plano escrito que um executor competente seguiria sem
voltar a perguntar.

## Fase 5 — Executar

**Objetivo:** implementar o plano, uma etapa por vez.

1. Execute **uma etapa por vez**; complete o critério de pronto antes de
   iniciar a próxima.
2. Quando houver código, use **TDD**: escreva o teste que falha → veja-o
   falhar → implemente o mínimo → veja-o passar → refatore. Teste que nunca
   falhou não prova nada.
3. Ao encontrar um bug ou comportamento inesperado, **pare de implementar e
   depure sistematicamente**: reproduza → formule uma hipótese → teste a
   hipótese → só então corrija. Nunca empilhe correções por tentativa.
4. Se o escopo crescer no meio da tarefa, **pare e avise**. Escopo novo passa
   pelo gate da Fase 3 — não é "só mais uma coisinha".
5. Commits e pushes: somente quando o usuário pedir. Em branch default, crie
   uma branch antes.
6. Se uma etapa for pulada ou adaptada, registre e informe — nunca
   silenciosamente.

**Saída da fase:** todas as etapas do plano concluídas, cada uma com seu
critério de pronto cumprido.

## Fase 6 — Verificar

**Objetivo:** provar que funciona antes de declarar pronto.

1. Rode os comandos de verificação (testes, build, lint, execução real da
   aplicação) e **leia a saída completa**.
2. Afirme sucesso apenas sobre o que você viu passar. "Deve funcionar" é
   proibido; "rodei X e a saída foi Y" é o padrão.
3. Falhou? Reporte com a saída real e volte para a Fase 5, item 3 (debug
   sistemático). Não mascare, não pule, não "arrume o teste" para passar.
4. Verifique também o que o plano prometeu fim-a-fim, não só as partes
   isoladas.

**Saída da fase:** evidência concreta (saídas de comandos) de que tudo que
foi prometido funciona.

## Fase 7 — Entregar

**Objetivo:** devolver o trabalho de forma que o usuário entenda em 30
segundos.

1. **Lidere com o resultado:** a primeira frase responde "o que aconteceu".
   Detalhes e justificativas vêm depois.
2. Liste o que mudou (arquivos, comportamento) e o que foi verificado, com
   evidência.
3. Declare as escolhas que você fez por conta própria, para o usuário poder
   revisá-las.
4. Peça review quando o trabalho for significativo. Integre (merge/PR/deploy)
   somente com autorização explícita.
5. Ofereça próximos passos como sugestão — nunca como trabalho já iniciado
   sem pedir.

**Saída da fase:** usuário informado do resultado, das evidências e das
escolhas feitas, com a integração aguardando a autorização dele.

## Anti-padrões

| Racionalização | Conduta correta |
|---|---|
| "É só uma mudança simples, não precisa de processo" | Mudanças simples viram complexas. Classifique na Fase 1 e siga o fluxo. |
| "Vou assumir um default sensato" | Pode — desde que dito em voz alta. Default silencioso é proibido. |
| "Preciso explorar o código antes de perguntar o porquê" | Exploração responde "como é hoje"; só o usuário responde "por quê". São perguntas diferentes. |
| "O usuário disse 'parece bom' à ideia, posso construir" | Aprovação cobre o que foi mostrado. Design não escrito não foi aprovado. |
| "Os testes devem passar, a mudança é pequena" | Rode. Leia a saída. Só então afirme. |
| "Vou corrigir esse bug rapidinho enquanto implemento" | Pare. Reproduza, hipótese, teste. Correção no chute gera dois bugs. |
| "Já que estou aqui, aproveito e melhoro X" | Escopo novo = volta ao gate da Fase 3. |
| "Vou commitar para não perder o trabalho" | Commit só com pedido do usuário. |
| "O teste falha por motivo não relacionado, vou ignorar" | Investigue ou reporte. Nunca ignore silenciosamente. |

## Integração com outras skills

Se o ambiente tiver as skills abaixo instaladas, **invoque-as** na fase
correspondente em vez de improvisar:

| Fase | Skill |
|---|---|
| 1–3 (entender, explorar, desenhar) | `superpowers:brainstorming` |
| 4 (planejar) | `superpowers:writing-plans` |
| 5 (executar) | `superpowers:executing-plans` ou `superpowers:subagent-driven-development` |
| 5 (código novo) | `superpowers:test-driven-development` |
| 5 (bug encontrado) | `superpowers:systematic-debugging` |
| 5 (isolamento de workspace) | `pr-worktree` ou `superpowers:using-git-worktrees` |
| 6 (verificar) | `superpowers:verification-before-completion` |
| 7 (entregar) | `superpowers:requesting-code-review` → `superpowers:finishing-a-development-branch` |

Nenhuma delas é pré-requisito: sem elas, as fases deste documento bastam.
