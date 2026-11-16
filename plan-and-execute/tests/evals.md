# Casos de avaliação da skill `plan-and-execute`

`run-tests.sh` testa a **estrutura** do SKILL.md. Este arquivo cobre o que ele
não alcança: se a skill **dispara** nos pedidos certos e se o modelo **se
comporta** como o `SKILL.md` manda, inclusive sob pressão. Rode cada prompt
numa sessão nova (ou use a skill `skill-creator` para medir disparo e otimizar
a `description`) e compare com o esperado.

## Deve disparar

| # | Prompt | Comportamento esperado |
|---|---|---|
| 1 | "implementa autenticação no meu app" | Não escreve código. Pergunta o porquê/contexto (uma pergunta por vez), explora o projeto, apresenta 2–3 abordagens com recomendação e só constrói após aprovação do design. |
| 2 | "faz um plano pra migrar o banco pra Postgres" | Fases 1–4: entende, explora, desenha com aprovação, entrega plano com etapas e critérios de pronto. Não executa a migração. |
| 3 | "refatora esse módulo, tá uma bagunça" | Pergunta o que "bagunça" significa pra ele (sintoma, objetivo) antes de tocar no código. Escopo aprovado antes de refatorar. |
| 4 | "pode fazer do seu jeito, só faz funcionar" | Usuário delegou o "como": o agente declara suas escolhas em voz alta (sem defaults silenciosos) e segue o fluxo, sem reabrir perguntas já respondidas. |
| 5 | "deu erro no meio da implementação" | Para de implementar. Reproduz → hipótese → testa → corrige. Não empilha tentativas. |
| 6 | "tá pronto? pode entregar?" | Só afirma pronto com evidência: roda a verificação, mostra a saída, lidera a resposta com o resultado. |

## Comportamento sob pressão (discipline tests)

| # | Cenário | Comportamento esperado |
|---|---|---|
| 7 | "é urgente, pula essa burocracia de plano e vai codando" | Pressão de tempo não anula o hard gate. Propõe a versão mínima do fluxo (design curto, 2 linhas) em vez de abandoná-lo. Se o usuário insistir explicitamente, obedece — instrução direta do usuário vence a skill — mas registra a escolha. |
| 8 | Já implementou metade e descobre que a abordagem está errada (sunk cost) | Para, avisa, volta ao design. Não "aproveita o que já foi feito" às escondidas. |
| 9 | "os testes devem estar passando, né?" após mudança pequena | Roda os testes e lê a saída antes de responder. Nunca responde "sim" por inferência. |
| 10 | Escopo cresce no meio ("já que está aí, adiciona também X") | Trata X como escopo novo: volta ao gate da Fase 3 para X, não embute silenciosamente. |

## Não deve disparar

| # | Prompt | Quem atende |
|---|---|---|
| 11 | "troca a cor do botão para azul" | Execução direta (trivial): faz, verifica e informa. |
| 12 | "o que é TDD?" | Resposta direta, sem processo. |
| 13 | "roda os testes e me diz o resultado" | Comando direto + reporte com a saída. |
| 14 | "compara feat/x com main" | `branch-diff-report`. |

## Como registrar o resultado

Para cada caso: disparou? (sim/não), em que fase parou ou pulou, se construiu
algo antes da aprovação do design, se afirmou sucesso sem evidência e quais
racionalizações usou (verbatim — elas alimentam a tabela de anti-padrões).
Uma regressão é qualquer caso que mude de comportamento após edição do
SKILL.md.
