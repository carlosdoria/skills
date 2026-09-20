# Claude Code Skills

Skills para Claude Code.

## Instalação remota

Depois de publicar este repositório no GitHub, o usuário poderá instalar as skills com:

```bash
curl -fsSL https://raw.githubusercontent.com/SEU-USUARIO/skills/main/install.sh | bash
```

> Substitua `SEU-USUARIO` pelo seu usuário do GitHub.

O instalador copia todas as skills para:

```text
~/.claude/skills/
```

Depois, abra uma nova sessão do Claude Code.

## Instalação local

Também é possível executar diretamente:

```bash
./install.sh
```

## Estrutura

```text
skills/
├── branch-diff-report/
│   └── SKILL.md
└── pr-worktree/
    └── SKILL.md
```

## Requisitos

- Bash
- Git
- Claude Code

O `gh` pode ser usado pelas skills que precisarem consultar PRs do GitHub.
