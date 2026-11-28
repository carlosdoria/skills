# Maestri: configuração do Maestro para o plugin demands

O que fica pronto ao final:
- um workspace do Maestri só para o `skills`;
- o papel `Maestro`, salvo nesse workspace e versionado no repositório;
- o Maestro implementando a V1 do demands pelo plano.

O papel nasce junto com o plugin: o texto fonte fica em `mods/demands/maestri/maestro-role.md`, e a cópia que o Maestri usa fica em `.maestri/roles/`, as duas no git.

## Como o Maestri estava em 2026-11-28

- App Maestri 0.61.2 aberto.
- O comando `maestri` só funciona dentro dos terminais do Maestri ("only available inside Maestri terminals").
- Havia um workspace em `~/repos/labs`, com o papel `Claude-Builder`. O `skills` não tinha workspace próprio.
- Os papéis de um workspace ficam na pasta dele, em `.maestri/roles/<id>/` (`role.json`, `CLAUDE.md`, `AGENTS.md`).
- O Maestro Mode é ligado por terminal, no canvas. Sem ele, os comandos de workspace e de rotina respondem "This terminal is not the Maestro".
- `maestri recruit` aceita `--dir` para a pasta de trabalho do recruta.
- O comando `code`, do VS Code, está no PATH.

## Passo a passo

1. Confira que a worktree de integração está limpa:

   ```bash
   git -C ~/repos/labs/skills/feat-demands-plugin status -sb
   ```

   Esperado: `## feat/demands-plugin...origin/feat/demands-plugin` e nenhum arquivo listado.

2. No Maestri, crie um workspace novo chamado `skills-demands` com a pasta `~/repos/labs/skills/feat-demands-plugin` (use o caminho completo ao escolher a pasta).
3. Nesse workspace, abra um terminal com o preset `Claude Code`, renomeie para `Maestro` e ligue o Maestro Mode nele, no canvas.
4. Cole o **Prompt 1** e espere o relatório.
5. Cole o **Prompt 2**. O Maestro para na Fase 1 com o plano da onda 1; responda "aprovado" ou peça ajustes.
6. Durante as ondas, ele pede o seu OK para: integrar cada onda em `feat/demands-plugin`, baixar as bibliotecas do dashboard (Tarefa 11) e abrir o PR.

## Prompt 1: configuração

```text
Configure este workspace para o plugin demands. Responda em português. Nesta tarefa: não crie floors, não recrute ninguém, não faça push.

1. Confira e me mostre o resultado de: pwd (tem que ser a worktree feat-demands-plugin), git branch --show-current (feat/demands-plugin), git status --porcelain (vazio), maestri list, maestri preset list, maestri role list, maestri recruit --help, command -v code, claude --version, node --version.
2. Se maestri role list já tiver um papel "Maestro", mostre com maestri role show "Maestro" e pare para eu decidir. Se não tiver, crie no escopo deste workspace:
   maestri role create "Maestro" "$(cat mods/demands/maestri/maestro-role.md)"
3. Confira que maestri role show "Maestro" bate com o arquivo e que git status --porcelain mostra só a pasta nova em .maestri/roles/. Se aparecer qualquer outra coisa dentro de .maestri/, não commite e me mostre.
4. Faça o commit só dessa pasta: git add .maestri/roles && git commit -m "chore: papel do Maestro no workspace do skills". Sem push.
5. Se este terminal não estiver em Maestro Mode, me avise.
6. Relatório: o que conferiu (comando e resultado), o id do papel, o SHA do commit e o que falhou.
```

## Prompt 2: execução do plano

```text
Leia mods/demands/maestri/maestro-role.md e siga esse texto como o seu papel nesta sessão (se você já começou com o papel "Maestro", é o mesmo texto).

Pedido: executar o plano docs/demands/2026-11-28-demands-plugin-v1-plan.md, seguindo a seção "Execução com o Maestro". A worktree de integração é esta, na branch feat/demands-plugin. O desenho está em docs/demands/2026-11-28-demands-plugin-design.md. Os recrutas usam o preset "Claude Code" e começam com --dir na própria worktree. Comece pela Fase 0 e pare na Fase 1 com o plano da onda 1 (frentes lib-core e security) para minha aprovação.
```

## Nas próximas vezes e no outro Mac

- **Mesmo Mac:** no workspace `skills-demands`, abra o terminal já com o papel `Maestro`, se a interface oferecer a escolha de papel, e ligue o Maestro Mode. Sem essa opção, use um terminal comum e comece pelo Prompt 2, que manda ler o papel do arquivo.
- **Outro Mac:** traga a branch (`git fetch` e a worktree de `feat/demands-plugin`, ou `git pull` na `main` depois do merge) e crie o workspace apontando para a mesma pasta. O papel vem junto, porque `.maestri/roles/` está no repositório. Confira com `maestri role list`.
- **Depois do merge:** crie um workspace para `~/repos/labs/skills/main`. O papel continua disponível lá.

## Próxima etapa: demands e Maestri juntos

Ainda não está no desenho; depende da V1 pronta e da sua aprovação.

- O papel do Maestro passa a usar o demands: cada frente vira uma demanda (`/demands:new`), planejada pelo `demands:planner` e aprovada por você. O recruta trabalha na própria worktree com a sua demanda em Fazendo, e a trava do demands libera só ali.
- `/demands:init`, rodando dentro de um terminal do Maestri, cria no projeto o papel `Maestro` a partir de `mods/demands/maestri/maestro-role.md`.
