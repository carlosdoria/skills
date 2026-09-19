---
name: branch-diff-report
description: Compara duas branches Git quaisquer e gera um relatório de revisão em Markdown a partir do diff — o que mudou e por quê, áreas do sistema afetadas, pontos de atenção classificados por risco, componentes alterados, arquivos sem cobertura de teste, mudanças de dependência e ordem sugerida de revisão. Funciona em qualquer repositório, sem worktree e sem alterar nada. Use sempre que o usuário pedir para comparar duas branches, ver o que mudou entre uma branch e outra, resumir ou analisar um PR, gerar relatório ou review de um diff, ou perguntar o que uma branch traz em relação à base, mesmo que não use as palavras relatório, diff ou o nome exato do comando.
---

# Branch Diff Report

Compara duas branches e escreve um relatório de revisão em Markdown.
É uma skill **somente leitura**: não cria worktree, não muda de branch, não
altera refs nem o working tree. Serve para qualquer repositório Git.

A coleta de dados está resolvida no script em `scripts/`. **Nunca
reimplemente essa lógica na mão** — sempre delegue para o script. O papel
desta skill é a camada de julgamento em volta dele: interpretar os fatos,
classificar risco, escrever o texto.

Outras skills (validação de PR com ou sem worktree) chamam esta aqui para a
parte do relatório. Quando for esse o caso, use `--dir` para apontar ao
diretório certo.

## Fluxo

### 1. Descubra as duas branches

- Se o usuário deu as duas, use-as direto.
- Se deu só uma, a outra é a base: tente `gh pr view <branch> --json baseRefName`
  ou use a branch padrão do remoto. Confirme com o usuário se houver dúvida.
- Se descreveu o PR em linguagem natural ("o PR do relatório do capitão"),
  tente `gh pr list` ou `gh search prs --repo <owner/repo> <termos>`.
- Se houver mais de uma candidata, pergunte qual — não adivinhe.

### 2. Colete os fatos

```bash
bash scripts/collect-branch-facts.sh <base-branch> <feature-branch> [--dir <caminho>] [--no-fetch]
```

A comparação sempre parte do **merge-base** entre as duas, não da ponta da
base — assim commits que entraram na base depois que a feature saiu não
poluem o diff.

O script devolve **apenas dados brutos e verificáveis**, em seções
delimitadas por `=== NOME ===`: metadados, autores, commits, totais, lista
de arquivos com status e +/-, arquivos mais alterados, sinalizadores de
arquivos sensíveis, diff dos manifestos de dependência, testes no diff e
componentes/hooks com contagem de consumidores.

Ele não classifica risco nem escreve texto — isso é trabalho seu.

### 2. Interprete

As heurísticas do script são um ponto de partida, não a verdade. Antes de
escrever, abra os arquivos que importam:

- **Leia o diff dos arquivos de maior risco** antes de afirmar qualquer
  coisa sobre eles. Um webhook sinalizado como "endpoint público" pode já
  ter validação de assinatura — verifique em vez de repetir a heurística.
- **Agrupe por área do sistema**, não por pasta. "Checkout (UI)" e
  "Pagamentos (core)" dizem mais ao revisor do que `src/components/`.
- **Descreva a intenção do PR em linguagem humana**, a partir dos commits
  e do diff, não do título da branch.
- **Só afirme o que você verificou.** Se não conseguiu determinar algo
  (ex.: quem consome um componente), diga que não foi verificado em vez de
  chutar. Melhor uma linha a menos do que uma linha errada.

### 3. Classifique o risco

| Nível | Critério |
|---|---|
| Alto | Migração de banco, mudança em rota pública, autenticação/permissão, remoção de campo ou endpoint, mudança de contrato consumida por terceiros |
| Médio | Mudança de contrato interno, config/env nova, dependência atualizada com major bump, alteração em código compartilhado sem teste |
| Baixo | UI sem lógica nova, renomeações, texto, testes, documentação |

Se nada se enquadrar em Alto ou Médio, diga isso explicitamente em vez de
inflar a tabela para parecer completa.

### 4. Escreva o relatório

Mostre o relatório na conversa. Se o usuário pedir um arquivo, salve como
`PR-REVIEW.md` na raiz do repositório onde a comparação foi feita. Use este
formato — ícones **apenas** nos três títulos indicados, em nenhum outro
lugar:

````markdown
# Revisão: <branch>

**Branch base:** `<base>` · **Autor:** <autor> · **Commits:** <n>
**<n> arquivos** alterados · `+<n>` / `−<n>`
---

## O que este PR faz

<2 a 4 linhas em linguagem humana: o que muda e por quê.>

| Área | Arquivos | O que mudou |
|---|---|---|
| <área do sistema> | <n> | <uma frase> |

---

## ⚠️ Pontos de atenção

| Risco | Onde | Por quê |
|---|---|---|
| Alto/Médio/Baixo | `<caminho>` | <motivo concreto e verificado> |

---

## Componentes alterados

| Componente | Tipo | Consumidores |
|---|---|---|
| `<Nome>` | Novo / Modificado / Modificado (hook) | <n> |

<Uma linha apontando componentes compartilhados e o que mais pode quebrar.>

---

## 🧪 Sem cobertura de teste

Arquivos de código alterados que não têm teste correspondente no diff:

- `<caminho>`

Cobertura no diff: **<n> de <n>** arquivos de lógica.

---

## 📦 Dependências

| Pacote | Versão | Situação |
|---|---|---|
| `<pacote>` | `<versão>` ou `<antiga>` → `<nova>` | Nova / Atualizada / Removida |

---

## Ordem sugerida de revisão

1. `<caminho>` — <por que começar aqui>
````

### Regras de formatação

- **Seções vazias são omitidas**, não preenchidas com "nenhum". Se o PR
  não mexe em dependências, a seção `📦 Dependências` simplesmente não
  aparece.
- **Ícones com moderação**: só os três já previstos no modelo. Nenhum
  ícone em tabelas, listas ou corpo de texto.
- **Diffs pequenos** (menos de ~5 arquivos ou só texto/config) recebem uma
  versão curta: cabeçalho, "O que este PR faz" e "Pontos de atenção".
  Não force o formato completo.
- **A ordem sugerida de revisão vai do maior risco ao menor**, não da
  maior pasta à menor.
- O relatório é um mapa para o revisor humano, não um veredito. Não
  aprove nem rejeite o PR.

## Pré-requisitos

- `git`.
- `gh` (GitHub CLI), opcional — só para descobrir a branch base de um PR ou
  achar a branch a partir de uma descrição em linguagem natural.

## Referência rápida dos scripts

- `scripts/collect-branch-facts.sh <base-branch> <feature-branch> [--dir <caminho>] [--no-fetch]`
  — resolve as duas branches (preferindo `origin/`), calcula o merge-base e
  imprime os fatos brutos do diff. Somente leitura. `--dir` aponta o
  repositório ou worktree onde operar (padrão: diretório atual);
  `--no-fetch` pula a atualização do remoto.
