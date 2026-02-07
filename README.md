<!--
SPDX-FileCopyrightText: 2025 Zach Daniel
SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs.contributors>

SPDX-License-Identifier: MIT
-->
[![CI](https://github.com/ash-project/usage_rules/actions/workflows/elixir.yml/badge.svg)](https://github.com/ash-project/usage_rules/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/usage_rules.svg)](https://hex.pm/packages/usage_rules)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/usage_rules)
[![REUSE status](https://api.reuse.software/badge/github.com/ash-project/usage_rules)](https://api.reuse.software/info/github.com/ash-project/usage_rules)

# UsageRules

**UsageRules** is a config-driven dev tool for Elixir projects that manages your AGENTS.md file and agent skills from dependencies. It:

- Gathers and consolidates `usage-rules.md` files from your dependencies into an AGENTS.md (or any file)
- Generates agent skills (SKILL.md files) from dependency usage rules
- Provides built-in usage rules for Elixir and OTP
- Includes a powerful documentation search task via `mix usage_rules.search_docs`

## Quickstart

### Installation

If you have [igniter](https://github.com/ash-project/igniter) installed:

```sh
mix igniter.install usage_rules
```

Or add `usage_rules` manually to your `mix.exs`:

```elixir
def deps do
  [
    {:usage_rules, "~> 0.2", only: [:dev]},
    {:igniter, "~> 0.6", only: [:dev]}
  ]
end
```

### Configuration

All configuration lives in your `mix.exs` project config. Add a `:usage_rules` key:

```elixir
def project do
  [
    app: :my_app,
    # ...
    usage_rules: usage_rules()
  ]
end

defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: :all,
    link_to_folder: "deps"
  ]
end
```

Then run:

```sh
mix usage_rules.sync
```

That's it. The config is the source of truth — packages in the file but not in config are automatically removed on each sync.

## Configuration Reference

```elixir
defp usage_rules do
  [
    # The file to write usage rules into (required for usage_rules syncing)
    file: "AGENTS.md",

    # Which packages to include (required for usage_rules syncing)
    # :all discovers every dependency with a usage-rules.md
    usage_rules: :all,
    # Or list specific packages and sub-rules:
    # usage_rules: [
    #   :ash,                    # main usage-rules.md
    #   "phoenix:ecto",          # specific sub-rule
    #   :elixir,                 # built-in Elixir rules
    #   :otp,                    # built-in OTP rules
    # ],

    # Link style instead of inlining full content (recommended)
    link_to_folder: "deps",      # links to deps/<pkg>/usage-rules.md
    # link_to_folder: "rules",   # copies files into rules/ folder and links there
    link_style: "markdown",      # "markdown" (default) or "at" for @-style links

    # Force-inline specific packages even when using link_to_folder
    inline: ["usage_rules:all"],

    # Agent skills configuration
    skills: [
      location: ".claude/skills",  # where to output skills (default)

      # Auto-build a "use-<pkg>" skill per dependency
      deps: [:ash, :req],
      # Supports regex for matching multiple deps:
      # deps: [~r/^ash_/],

      # Compose custom skills from multiple packages
      build: [
        "ash-expert": [
          description: "Expert on the Ash Framework ecosystem.",
          usage_rules: [:ash, :ash_postgres, :ash_phoenix]
        ]
      ]
      # build also supports regex in usage_rules:
      # build: [
      #   "ash-expert": [
      #     description: "Expert on Ash.",
      #     usage_rules: [:ash, ~r/^ash_/]
      #   ]
      # ]
    ]
  ]
end
```

### Config options

| Option | Type | Description |
|--------|------|-------------|
| `file` | `string` | Target file for usage rules (e.g. `"AGENTS.md"`, `"CLAUDE.md"`) |
| `usage_rules` | `:all \| list` | Which packages to sync. `:all` auto-discovers, or list specific packages |
| `link_to_folder` | `string \| nil` | Create links instead of inlining. `"deps"` links to dep sources directly |
| `link_style` | `"markdown" \| "at"` | Link format. `"at"` uses `@path` style (default: `"markdown"`) |
| `inline` | `list` | Force-inline specific packages when using `link_to_folder` |
| `skills` | `keyword` | Agent skills configuration (see below) |

### Skills options

| Option | Type | Description |
|--------|------|-------------|
| `location` | `string` | Output directory for skills (default: `".claude/skills"`) |
| `deps` | `list` | Auto-build a `use-<pkg>` skill per listed dependency. Supports atoms and regexes |
| `build` | `keyword` | Define custom composed skills from multiple packages' usage rules |

## Usage Rules

### Sync all dependencies

The simplest setup — discover all deps with `usage-rules.md` and link to them:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: :all,
    link_to_folder: "deps"
  ]
end
```

### Specific packages

Pick exactly which packages to include:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:ash, :phoenix, :ecto],
    link_to_folder: "deps"
  ]
end
```

### Sub-rules

Packages can provide sub-rules in a `usage-rules/` directory. Reference them with `"package:sub_rule"` syntax:

```elixir
usage_rules: [:phoenix, "phoenix:ecto", "phoenix:html"]
```

Use `"package:all"` to include all sub-rules from a package:

```elixir
usage_rules: [:phoenix, "phoenix:all"]
```

### Built-in aliases

UsageRules ships with built-in rules for Elixir and OTP:

```elixir
usage_rules: [:elixir, :otp, :ash, :phoenix]
```

### Inline with folder links

When using `link_to_folder`, you can force specific packages to be inlined:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:ash, :phoenix, :usage_rules],
    link_to_folder: "deps",
    inline: ["usage_rules:all"]  # inline the usage_rules package's built-in rules
  ]
end
```

## Agent Skills

Skills are SKILL.md files that agent tools like Claude Code can discover and use. UsageRules can automatically generate skills from your dependencies' usage rules.

### Auto-build skills from deps

The `deps` option auto-builds a `use-<package>` skill for each listed dependency:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: :all,
    link_to_folder: "deps",
    skills: [
      deps: [:ash, :req]
    ]
  ]
end
```

This generates `.claude/skills/use-ash/SKILL.md` and `.claude/skills/use-req/SKILL.md`, each containing the package's usage rules, available mix tasks, doc search commands, and sub-rule references.

### Compose custom skills

The `build` option lets you compose a single skill from multiple packages:

```elixir
skills: [
  build: [
    "ash-expert": [
      description: "Expert on the Ash Framework ecosystem.",
      usage_rules: [:ash, :ash_postgres, :ash_phoenix, :ash_json_api]
    ]
  ]
]
```

This generates a single `.claude/skills/ash-expert/SKILL.md` that combines usage rules from all listed packages. Regex is also supported:

```elixir
skills: [
  build: [
    "ash-expert": [
      description: "Expert on Ash.",
      usage_rules: [:ash, ~r/^ash_/]
    ]
  ]
]
```

### Stale skill cleanup

Skills generated by UsageRules include a `managed-by: usage-rules` marker in their YAML frontmatter. When a skill is removed from your config and you re-run `mix usage_rules.sync`, the stale skill files are automatically cleaned up.

### Skills-only mode

You can use skills without syncing usage rules into a file — just omit the `file` and `usage_rules` keys:

```elixir
defp usage_rules do
  [
    skills: [
      deps: [:ash, :phoenix]
    ]
  ]
end
```

## Documentation Search

`mix usage_rules.search_docs` searches hexdocs with human-readable markdown output, designed for both humans and AI agents.

```sh
# Search all project dependencies
mix usage_rules.search_docs "search term"

# Search specific packages
mix usage_rules.search_docs "search term" -p ecto -p ash

# Search specific versions
mix usage_rules.search_docs "search term" -p ecto@3.13.2

# Search all packages on hex
mix usage_rules.search_docs "search term" --everywhere

# JSON output
mix usage_rules.search_docs "search term" --output json

# Search only in titles
mix usage_rules.search_docs "search term" --query-by title

# Pagination
mix usage_rules.search_docs "search term" --page 2 --per-page 20
```

## For Package Authors

Even if you don't use LLMs yourself, your users likely do. Writing a `usage-rules.md` file helps prevent hallucination-driven support requests.

We don't really know what makes great usage-rules.md files yet. Ash Framework is experimenting with quite fleshed out usage rules which seems to be working quite well. See [Ash Framework's usage-rules.md](https://github.com/ash-project/ash/blob/main/usage-rules.md) for one such large example. Perhaps for your package only a few lines are necessary.

One quick tip is to have an agent begin the work of writing rules for you, by pointing it at your docs and asking it to write a `usage-rules.md` file in a condensed format that would be useful for agents to work with your tool. Then, aggressively prune and edit it to your taste.

Make sure that your `usage-rules.md` file is included in your hex package's `files` option, so that it is distributed with your package.

### Sub-rules

A package can provide a main `usage-rules.md` and/or sub-rule files:

```
usage-rules.md          # general rules
usage-rules/
  html.md               # html specific rules
  database.md           # database specific rules
```

### Migrating from v0.1

v0.2 replaces CLI arguments with project config. If you were running:

```sh
mix usage_rules.sync AGENTS.md --all --link-to-folder deps
```

Replace it with config in `mix.exs`:

```elixir
def project do
  [
    usage_rules: [
      file: "AGENTS.md",
      usage_rules: :all,
      link_to_folder: "deps"
    ]
  ]
end
```

Then just run `mix usage_rules.sync` with no arguments.
