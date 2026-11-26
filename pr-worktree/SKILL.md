---
name: pr-worktree
description: Gerencia worktrees Git no padrão bare + worktree por branch — clona um repositório já nesse formato, converte um existente, cria worktree com branch nova a partir de uma base ou de outra worktree, lista, atualiza e remove com segurança. Também prepara e limpa worktrees descartáveis para revisar, rodar e testar um PR localmente. Use quando o usuário pedir para clonar um repositório, criar, abrir, listar, atualizar ou remover uma worktree, branch ou pasta de trabalho, ou revisar, testar ou rodar um PR localmente, mesmo sem dizer "worktree".
---

# PR Worktree

Cuida de worktrees Git em dois usos com ciclos de vida diferentes:

- **Desenvolvimento** — vida longa, branch de verdade, onde se escreve
  código. Criar, listar, atualizar, remover (abaixo).
- **Validação de PR** — descartável, em HEAD *detached*, com o diff inteiro
  do PR aparecendo como alteração não commitada, sem tocar na branch
  original nem no diretório de trabalho do usuário.

Nunca trate um como o outro: worktree de PR não se atualiza (se recria), e
worktree de desenvolvimento não se descarta sem checar trabalho não salvo.

Toda a lógica de Git está nos scripts em `scripts/`. **Nunca reimplemente
essa lógica na mão.** O papel desta skill é o julgamento em volta deles:
entender o pedido, resolver ambiguidades, resumir resultados. Quando um
script recusa, a mensagem diz o motivo: mostre-a ao usuário e leve a
decisão a ele.

## Antes de agir, leia o arquivo do pedido

| Pedido | Leia antes de rodar qualquer script |
|---|---|
| Clonar um repositório; converter um projeto para bare | `references/padrao-bare.md` |
| Revisar, validar, testar ou rodar um PR; limpar essa validação | `references/validacao-pr.md` |
| Criar, listar, atualizar ou remover worktree de desenvolvimento | só este arquivo |

Os caminhos `scripts/...` são relativos à pasta desta skill, também nas
referências.

## Padrão: repositório bare + worktree por branch

Nenhuma branch, nem a `main`, fica com checkout direto na raiz do projeto.
A raiz é só o repositório bare (`<projeto>/.bare`), e toda branch vive numa
worktree irmã (`<projeto>/main`, `<projeto>/minha-feature`). Para saber se
um projeto já é bare, use `git rev-parse --is-bare-repository` ou a saída
de `list` (seção "REPOSITÓRIO (bare, sem working tree própria)"). Num
projeto bare, a base para `--from` costuma ser a worktree `<projeto>/main`.

## Regra: confirmar a pasta antes de criar

Antes de **criar um projeto** (`clone`) ou **uma worktree** (`new`),
confirme com o usuário em qual pasta — **sempre**, mesmo que o padrão do
script pareça óbvio. Só rode depois da resposta.

- **Mostre o caminho absoluto resolvido** e o que será criado ali. Ex.:
  "Vou clonar em `/Users/x/repos/foo` (cria `foo/.bare` e `foo/main`). Pode
  ser aí ou prefere outra pasta?"
  - `clone` sem `--dir` cria `<pasta atual>/<nome-do-repo>`.
  - `new` sem `--dir` cria a worktree como pasta irmã na raiz do projeto
    (`<raiz do projeto>/<nome-derivado-da-branch>`), que **não é
    necessariamente a pasta atual**.
- **Única exceção:** o usuário deixou claro que é na pasta atual ("aqui",
  "nesta pasta", "no diretório atual"). Aí não pergunte: crie e informe o
  caminho. No `new`, passe `--dir "$PWD/<nome-derivado-da-branch>"`; no
  `clone`, o padrão já é a pasta atual.
- Pedido genérico ("cria uma worktree pra feature/x") ou caminho citado de
  passagem **não** dispensam a pergunta.
- Outra pasta indicada vai em `--dir`: no `clone`, é a pasta do projeto; no
  `new`, é o caminho da própria worktree (pasta escolhida + nome derivado
  da branch), não a pasta-pai.
- A confirmação vale só para o pedido em curso.

`bootstrap-bare` não entra nessa regra (converte em lugar uma pasta que o
usuário já indicou), nem o worktree de validação de PR (caminho fixo, sem
`--dir`).

## Worktrees de desenvolvimento

Todos os subcomandos: `bash scripts/manage-worktree.sh <subcomando> [args]`.

- **Criar:** `new <nova-branch> [--from <base>] [--dir <caminho>]`.
  `--from` aceita o caminho de outra worktree ou um nome de branch; a base é
  atualizada por fast-forward antes. Sem `--from`, usa a branch padrão do
  remoto. "Abre uma pasta nova pra feature/abc saindo da irop-report" é
  `new feature/abc --from <caminho da irop-report>`.
- **Criar a branch não é commitar.** Só crie. Não faça `git add`,
  `git commit`, `cherry-pick` nem `push`, e não leve arquivos alterados ou
  novos para a branch: eles ficam como estão, sem commit. Só commite e
  publique quando o usuário pedir, e só o que foi pedido. Na dúvida sobre o
  que entra na branch, pergunte.
- **Listar:** `list`. Separa a entrada bare, o desenvolvimento e a
  validação de PR, e marca alterações não salvas. Use antes de remover e
  quando perguntarem o que está aberto.
- **Atualizar:** `update [<alvo>]` (sem alvo, a worktree atual). Só
  fast-forward: se as pontas divergiram, o script recusa e mostra o comando
  de rebase, mas quem decide rebasear é o usuário.
- **Remover:** `remove <alvo> [--force]`, com `<alvo>` sendo o caminho ou o
  nome da branch. O script protege trabalho não salvo e nunca apaga a
  branch (diz se ela já foi mesclada e deixa o `git branch -d` para o
  usuário). A worktree da branch padrão (`<projeto>/main`) **não** é
  protegida: confirme com o usuário antes de removê-la. Antes de `--force`,
  mostre o que será perdido (o erro traz `git status --short`) e peça
  confirmação.

## Regras de segurança (nunca violar)

- Não rode `clone` nem `new` sem confirmar a pasta (salvo o pedido explícito
  de criar na pasta atual).
- Não commite, faça push, rebase, force push nem apague branch sem o usuário
  pedir.
- Não passe `--force` nem `--confirmo-riscos` por iniciativa própria. As
  recusas dos scripts são proteções, não obstáculos: leve a decisão ao
  usuário.
- Não edite refs, não rode `git reset` fora dos scripts e não conserte uma
  worktree na mão. Se um script falhar, reporte o erro em vez de contornar
  com comandos Git manuais.
