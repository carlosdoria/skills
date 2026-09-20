---
name: pr-worktree
description: Gerencia worktrees Git de um projeto — cria uma worktree nova com branch nova a partir de uma base, lista as ativas, atualiza por fast-forward e remove com segurança — e também prepara e limpa worktrees descartáveis para revisar, rodar e testar um Pull Request sem tocar na branch original nem no diretório de trabalho do usuário. Funciona em qualquer repositório Git, com ou sem setup prévio de worktrees. Use sempre que o usuário pedir para criar, abrir, listar, atualizar ou remover uma worktree ou uma pasta de trabalho para uma branch, pedir uma worktree a partir de outra ou baseada em outra, ou pedir para revisar, validar, testar ou rodar um PR localmente e depois finalizar e limpar essa validação, mesmo que não use a palavra worktree nem o nome exato do comando. Para o relatório escrito da revisão, esta skill delega para a skill branch-diff-report.
---

# PR Worktree

Cuida de worktrees Git em dois usos que têm ciclos de vida diferentes:

- **Worktrees de desenvolvimento** — vida longa, branch de verdade, onde se
  escreve código. Criar, listar, atualizar, remover.
- **Worktrees de validação de PR** — descartáveis, em HEAD *detached*, para
  revisar e testar um Pull Request com o diff inteiro aparecendo como
  alteração não commitada, sem tocar na branch original nem no diretório de
  trabalho do usuário.

Nunca trate um como o outro: worktree de PR não se atualiza (se recria), e
worktree de desenvolvimento não se descarta sem checar trabalho não salvo.

Toda a lógica de Git (fetch, merge-base, `worktree add`, `reset`, remoção)
já está resolvida nos scripts em `scripts/`. Não é preciso nenhum
setup especial de worktrees no projeto: funciona num clone comum. **Nunca reimplemente essa
lógica na mão** — sempre delegue para os scripts. O papel desta skill é a
camada de julgamento em volta deles: entender o pedido em linguagem natural,
resolver ambiguidades, resumir resultados.

## Fluxo: worktrees de desenvolvimento

Todos os subcomandos são do mesmo script:

```bash
bash scripts/manage-worktree.sh <subcomando> [args]
```

### Criar

```bash
bash scripts/manage-worktree.sh new <nova-branch> [--from <base>] [--dir <caminho>]
```

`--from` aceita o **caminho de outra worktree** ou um **nome de branch**. A
base é atualizada por fast-forward antes, para a branch nova não nascer
atrasada. Sem `--from`, usa a branch padrão do remoto. A worktree é criada
como pasta irmã da raiz do projeto, com o nome derivado da branch, a menos
que `--dir` diga outro lugar.

Se o usuário disser algo como "abre uma pasta nova pra feature/abc saindo da
irop-report", isso é `new feature/abc --from <caminho da irop-report>`.

**Criar a branch não é commitar.** Quando o usuário pedir para criar uma
branch (ou uma worktree), apenas crie-a. Não faça `git add`, `git commit`,
`cherry-pick` nem `push`, e não leve arquivos alterados ou novos para a
branch: eles ficam como estão no working tree, sem commit. Só commite e
publique quando o usuário pedir isso explicitamente, e nesse caso faça só
o que foi pedido. Em caso de dúvida sobre o que entra na branch, pergunte.

### Listar

```bash
bash scripts/manage-worktree.sh list
```

Separa as de desenvolvimento das de validação de PR e marca as que têm
alterações não salvas. Use antes de remover qualquer coisa, e sempre que o
usuário perguntar o que está aberto.

### Atualizar

```bash
bash scripts/manage-worktree.sh update [<alvo>]
```

**Somente fast-forward.** Se as pontas divergiram, o script recusa e mostra
o comando de rebase — mas quem decide rebasear é o usuário, nunca você.
Sem argumento, atualiza a worktree atual.

### Remover

```bash
bash scripts/manage-worktree.sh remove <alvo> [--force]
```

Recusa se houver trabalho não salvo, se o alvo for a worktree principal, ou
se você estiver dentro dela. A branch nunca é apagada junto: o script
informa se ela já foi mesclada e deixa o `git branch -d` para o usuário.

**Antes de usar `--force`, mostre ao usuário o que será perdido** (a saída
do erro já traz `git status --short`) e peça confirmação explícita. Não
passe `--force` por iniciativa própria.

`<alvo>` pode ser o caminho da worktree ou o nome da branch.

## Fluxo: preparar um PR para revisão

1. **Descobrir a branch de feature certa.**
   - Se o usuário já deu o nome da branch, use-o diretamente.
   - Se ele descreveu o PR em linguagem natural (ex.: "o PR do relatório do
     capitão"), tente `gh pr list` ou `gh search prs --repo <owner/repo>
     <termos>` para encontrar a branch correspondente.
   - Se houver mais de um PR/branch parecido, pergunte qual antes de
     prosseguir — não adivinhe.

2. **Rodar o script principal:**
   ```bash
   bash scripts/prepare-pr-validation.sh <feature-branch> [--base <base-branch>]
   ```
   - Se já existir um worktree para o PR, o script só o recria quando ele
     não tiver edições do usuário além do PR. Com edições (ou sem como
     verificar, em registros antigos), ele aborta e lista os arquivos;
     `--force` recria mesmo assim e descarta essas edições.
   - Deixe o script detectar a branch base sozinho (via `gh`) sempre que
     possível; só passe `--base` se o script falhar em detectar ou o
     usuário indicar explicitamente uma base diferente.
   - O script **não abre nenhum editor**. Ele apenas cria o worktree e
     imprime o caminho — o usuário escolhe com o que abrir.

3. **Entre no worktree** (`cd <worktree_path>`) e rode dali em diante os
   comandos de revisão. Informe o caminho ao usuário para que ele abra no
   editor que preferir. Nunca execute `code`, `cursor`, `idea` ou qualquer
   outro editor por conta própria — só faça isso se o usuário pedir
   explicitamente, e com a ferramenta que ele nomear.

4. **Leia a saída do script** (caminho do worktree, branch, base,
   merge-base) e diga o que o PR muda. Não pare em "worktree criado".

5. Avise que o worktree tem um `CLAUDE.md` na raiz explicando o contexto
   (HEAD detached, o que pode/não pode fazer ali). Se você mesmo estiver
   operando dentro desse worktree numa sessão futura, leia esse arquivo
   primeiro.

6. **Ofereça os próximos passos** em vez de assumir: rodar os testes do
   projeto, rodar a aplicação, ou aprofundar em algum ponto de atenção do
   relatório.

## Fluxo: relatório de revisão

**Ao terminar qualquer trabalho neste fluxo** (validar o PR, corrigir algo
a pedido do usuário, rodar testes), **gere o relatório com a skill
`branch-diff-report` sem esperar o usuário pedir**, antes de limpar o
worktree. Se o trabalho mudou a branch (commits novos), gere o relatório
sobre o estado final. Entregue o relatório e só então ofereça o cleanup.

O relatório escrito não é responsabilidade desta skill. Use a skill
**`branch-diff-report`**, que compara duas branches e escreve o Markdown.

Passe o worktree recém-criado como diretório de trabalho:

```bash
bash <caminho-da-skill-branch-diff-report>/scripts/collect-branch-facts.sh \
  <base-branch> <feature-branch> --dir <worktree_path> --no-fetch
```

`--no-fetch` porque o `prepare` já atualizou as duas refs. A base e a
branch estão na saída do `prepare` e no registro
(`.git/pr-validation/active-worktrees`, no formato
`branch|base|caminho|merge-base|pr-head`).

Se a skill `branch-diff-report` não estiver disponível, diga isso ao
usuário em vez de improvisar um relatório próprio — o worktree já entrega
valor sozinho.

## Fluxo: limpar depois da revisão

0. Se o relatório final ainda não foi gerado nesta sessão, gere-o agora
   (seção anterior); depois do cleanup o worktree deixa de existir.
1. Confirme qual PR/worktree limpar. Se só um estiver ativo, use esse; se
   houver mais de um e o usuário não especificar, rode `git worktree list`,
   liste as opções e pergunte.
2. Rode:
   ```bash
   bash scripts/cleanup-pr-validation.sh <feature-branch>
   ```
   ou, para limpar tudo de uma vez:
   ```bash
   bash scripts/cleanup-pr-validation.sh --all
   ```
3. O cleanup só remove caminhos registrados pelo `prepare`, recusa o
   repositório principal e **preserva worktrees com edições do usuário**
   (arquivos que diferem do commit do PR), saindo com erro e listando-os.
   Ele nunca usa `rm -rf`: se o Git não conseguir remover, o script aborta.
   Só use `--force` depois de mostrar ao usuário o que será perdido e ele
   confirmar.
4. **Nunca rode o cleanup a partir de dentro do próprio worktree que está
   sendo removido** — o comando apaga aquele diretório. Rode sempre a
   partir do repositório principal (ou de outro worktree).

## Regras de segurança (nunca violar)

- Nunca commite nem faça push de arquivos ao criar uma branch ou worktree,
  a menos que o usuário peça isso explicitamente.
- Nunca faça `git commit`, `git push`, ou `git checkout <branch>` dentro do
  worktree de validação — o HEAD detached e o estado "resetado" são
  propositais, não um bug a corrigir.
- Nunca edite refs manualmente, rode `git reset` fora dos scripts, ou tente
  "consertar" o worktree na mão.
- Se um script falhar (branch não encontrada, base ambígua, worktree já
  existente e travado), reporte o erro ao usuário em vez de tentar
  contornar com comandos Git manuais.
- Nunca rebaseie, force push, apague branch ou passe `--force` (nos
  scripts `prepare`, `cleanup` e `manage-worktree remove`) por iniciativa
  própria. Essas recusas dos scripts são proteções, não
  obstáculos a driblar: leve a decisão ao usuário.

## Pré-requisitos

- `git` >= 2.5 (suporte a worktrees).
- `gh` (GitHub CLI), autenticado, para detecção automática da branch base e
  busca de PRs por descrição em linguagem natural. Sem ele, sempre passe
  `--base` explicitamente.

## Referência rápida dos scripts

- `scripts/manage-worktree.sh new|list|update|remove` — ciclo de vida das
  worktrees de desenvolvimento. `new` cria branch e worktree a partir de uma
  base atualizada; `list` separa desenvolvimento de validação de PR;
  `update` faz fast-forward e recusa divergência; `remove` protege trabalho
  não salvo e preserva a branch.

- `scripts/prepare-pr-validation.sh <feature-branch> [--base <branch>] [--force]`
  — cria/recria (protegendo edições do usuário) o worktree isolado, faz fetch, detecta a base, calcula o
  merge-base, reseta (mixed) em HEAD detached, gera o `CLAUDE.md` de
  contexto na raiz do worktree e imprime o caminho. Não abre editor algum.
- `scripts/cleanup-pr-validation.sh [<feature-branch> | --all] [--force]` —
  valida o caminho, protege edições do usuário, remove o worktree, roda `git worktree prune` e limpa o registro interno
  (`.git/pr-validation/` no repositório principal).
- `scripts/lib-pr-validation.sh` — funções compartilhadas (registro e
  detecção de edições); é lido com `source`, não é chamado direto.
- `tests/run-tests.sh` — testes de segurança do prepare/cleanup em repos
  temporários. Rode `bash tests/run-tests.sh` após alterar os scripts.
