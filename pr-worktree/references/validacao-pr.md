# Validação de PR: preparar, relatório, limpar

Caminhos `scripts/...` relativos à pasta da skill. O `gh` autenticado
detecta a base e acha PRs por descrição; sem ele, passe `--base`.

## Preparar

1. **Descubra a branch do PR.** Com o nome dado, use-o. Com uma descrição
   ("o PR do relatório do capitão"), tente `gh pr list` ou
   `gh search prs --repo <owner/repo> <termos>`. Mais de um candidato:
   pergunte qual, não adivinhe.
2. **Rode:**
   ```bash
   bash scripts/prepare-pr-validation.sh <feature-branch> [--base <base-branch>] [--force]
   ```
   - Deixe o script detectar a base; só passe `--base` se ele falhar ou o
     usuário indicar outra.
   - Se já existe worktree para o PR com edições do usuário, o script aborta
     e lista os arquivos. `--force` recria e descarta essas edições: só com
     confirmação explícita.
   - O script não abre editor. Nunca rode `code`, `cursor`, `idea` ou outro
     editor por conta própria; só se o usuário pedir, com a ferramenta que
     ele nomear.
3. **Entre no worktree** (`cd <worktree_path>`) e rode dali os comandos de
   revisão. Informe o caminho para o usuário abrir no editor que preferir.
4. **Diga o que o PR muda** a partir da saída (caminho, branch, base,
   merge-base). Não pare em "worktree criado".
5. Avise que o `CLAUDE.md` na raiz do worktree explica o contexto. Numa
   sessão futura dentro dele, leia-o primeiro.
6. **Ofereça os próximos passos** em vez de assumir: rodar os testes, rodar
   a aplicação ou aprofundar algum ponto.

Dentro do worktree de validação, nunca faça `git commit`, `git push` nem
`git checkout <branch>`: o HEAD detached e o estado resetado são
propositais, não um bug a corrigir.

## Relatório

**Ao terminar qualquer trabalho neste fluxo** (validar, corrigir algo a
pedido do usuário, rodar testes), **gere o relatório com a skill
`branch-diff-report` sem esperar o usuário pedir**, antes de limpar. Se o
trabalho criou commits na branch, gere sobre o estado final. Entregue o
relatório e só então ofereça o cleanup.

O script de coleta fica na skill irmã, `../branch-diff-report` a partir da
pasta desta skill. Passe o worktree como diretório:

```bash
bash <pasta-desta-skill>/../branch-diff-report/scripts/collect-branch-facts.sh \
  <base-branch> <feature-branch> --dir <worktree_path> --no-fetch
```

`--no-fetch` porque o `prepare` já atualizou as refs. Base e branch estão
na saída do `prepare` e em `.git/pr-validation/active-worktrees`
(`branch|base|caminho|merge-base|pr-head`).

Se a skill `branch-diff-report` não estiver disponível, diga isso ao
usuário em vez de improvisar um relatório; o worktree já entrega valor
sozinho.

## Limpar

0. Se o relatório final ainda não foi gerado, gere agora: depois do cleanup
   o worktree deixa de existir.
1. Confirme qual PR limpar. Um só ativo: esse. Mais de um sem indicação:
   rode `git worktree list`, mostre as opções e pergunte.
2. Rode `bash scripts/cleanup-pr-validation.sh <feature-branch>` ou, para
   limpar todos, `bash scripts/cleanup-pr-validation.sh --all`.
3. O cleanup preserva worktrees com edições do usuário e sai com erro
   listando os arquivos. Só use `--force` depois de mostrar o que será
   perdido e o usuário confirmar.
4. **Nunca rode o cleanup de dentro do worktree que será removido**: o
   comando apaga aquele diretório. Rode do repositório principal (no padrão
   bare, a raiz do projeto, onde fica o `.bare`) ou de outra worktree.
