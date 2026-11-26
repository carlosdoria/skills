# Publicar o resumo na descrição do PR

Só depois do OK explícito do usuário:

1. Leia a descrição atual com `gh pr view <n> --json body`.
2. Se ela estiver vazia, use o resumo como descrição. Se já tiver texto,
   pergunte se o resumo substitui o texto ou entra depois dele.
3. Grave o texto num arquivo temporário e rode
   `gh pr edit <n> --body-file <arquivo>`.
