<!--
SPDX-FileCopyrightText: 2025 Zach Daniel
SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>

SPDX-License-Identifier: MIT
-->
[![CI](https://github.com/ash-project/usage_rules/actions/workflows/elixir.yml/badge.svg)](https://github.com/ash-project/usage_rules/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/usage_rules.svg)](https://hex.pm/packages/usage_rules)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/usage_rules)
[![REUSE status](https://api.reuse.software/badge/github.com/ash-project/usage_rules)](https://api.reuse.software/info/github.com/ash-project/usage_rules)

# UsageRules

**UsageRules** is a config-driven dev tool for Elixir projects that manages your AGENTS.md file and agent skills from dependencies. It:

- Gathers and consolidates `usage-rules.md` files (or files from a `usage-rules` directory) from your dependencies into an `AGENTS.md` (or any file)
- Generates agent skills (`SKILL.md` files) from dependency usage rules
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
    {:usage_rules, "~> 1.1", only: [:dev]},
    {:igniter, "~> 0.6", only: [:dev]}
  ]
end
```

### Configuration

All configuration lives in your `mix.exs` project config. Add a `:usage_rules` key:

```elixir
def project do
  [
    ...
    usage_rules: usage_rules()
  ]
end

defp usage_rules do
  # Example for those using claude.
  [
    file: "CLAUDE.md",
    # rules to include directly in CLAUDE.md
    # use a regex to match multiple deps, or atoms/strings for specific ones
    usage_rules: [:ash, ~r/^ash_/],
    # If your CLAUDE.md is getting too big, link instead of inlining:
    usage_rules: [:ash, {~r/^ash_/, link: :markdown}],
    # or use skills
    skills: [
      location: ".claude/skills",
      # build skills that combine multiple usage rules
      build: [
        "ash-framework": [
          # The description tells people how to use this skill.
          description: "Use this skill working with Ash Framework or any of its extensions. Always consult this when making any domain changes, features or fixes.",
          # Include all Ash dependencies
          usage_rules: [:ash, ~r/^ash_/]
        ],
        "phoenix-framework": [
          description: "Use this skill working with Phoenix Framework. Consult this when working with the web layer, controllers, views, liveviews etc.",
          # Include all Phoenix dependencies
          usage_rules: [:phoenix, ~r/^phoenix_/]
        ]
      ]
    ]
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
    # :all discovers every dependency with a usage-rules.md and inlines them
    usage_rules: :all,
    # Or list specific packages and sub-rules:
    # usage_rules: [
    #   :ash,                         # inlined (default)
    #   ~r/^ash_/,                    # regex match (inlined)
    #   "phoenix:ecto",               # specific sub-rule (inlined)
    #   {:req, link: :at},            # linked with @-style
    #   {:ecto, link: :markdown},     # linked with markdown-style
    #   {~r/^phoenix_/, link: :markdown}, # regex match (linked)
    #   :elixir,                      # built-in Elixir rules
    #   :otp,                         # built-in OTP rules
    # ],

    # Agent skills configuration
    skills: [
      location: ".claude/skills",  # where to output skills (default)

      # Auto-build a "use-<pkg>" skill per dependency
      deps: [:ash, :req],
      # Supports regex for matching multiple deps:
      # deps: [~r/^ash_/],

      # Pull in pre-built skills shipped directly by packages
      package_skills: [:ash, ~r/^ash_/],

      # Compose custom skills from multiple packages
      build: [
        "ash-framework": [
          description: "Expert on the Ash Framework ecosystem.",
          usage_rules: [:ash, ~r/^ash_/]
        ]
      ]
    ]
  ]
end
```

### Config options

| Option | Type | Description |
|--------|------|-------------|
| `file` | `string` | Target file for usage rules (e.g. `"AGENTS.md"`, `"CLAUDE.md"`) |
| `usage_rules` | `:all \| list` | Which packages to sync. `:all` auto-discovers, or list specific packages |
| `skills` | `keyword` | Agent skills configuration (see below) |

### Usage rules entry format

Each entry in the `usage_rules` list can be:

| Format | Description |
|--------|-------------|
| `:package` | Inline the package's usage rules (default) |
| `"package:sub_rule"` | Inline a specific sub-rule |
| `"package:all"` | Inline all sub-rules from a package |
| `~r/pattern/` | Inline all matching dependencies' usage rules |
| `{:package, link: :at}` | Link with `@deps/package/usage-rules.md` style |
| `{:package, link: :markdown}` | Link with `[name](deps/package/usage-rules.md)` style |
| `{~r/pattern/, link: :markdown}` | Link all matching dependencies with markdown-style |
| `{"package:sub_rule", link: :at}` | Link a specific sub-rule with @-style |
| `{:package, main: false}` | Exclude the main `usage-rules.md`, include only sub-rules |

### Skills options

| Option | Type | Description |
|--------|------|-------------|
| `location` | `string` | Output directory for skills (default: `".claude/skills"`) |
| `deps` | `list` | Auto-build a `use-<pkg>` skill per listed dependency. Supports atoms and regexes |
| `build` | `keyword` | Define custom composed skills from multiple packages' usage rules |
| `package_skills` | `list` | Pull in pre-built skills shipped directly by packages. Supports atoms and regexes |

## Usage Rules

### Sync all dependencies

The simplest setup — discover all deps with `usage-rules.md` and inline them:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: :all
  ]
end
```

### Specific packages

Pick exactly which packages to include:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:ash, :phoenix, :ecto]
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

### Matching by regex

Use a regex to match multiple dependencies at once:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:ash, ~r/^ash_/]
    # If your AGENTS.md is getting too big, link instead of inlining:
    # usage_rules: [:ash, {~r/^ash_/, link: :markdown}]
  ]
end
```

This matches all dependencies whose name matches the regex and inlines their `usage-rules.md`. Dependencies without a `usage-rules.md` are silently skipped.

### Linking instead of inlining

By default, usage rules are inlined directly into the target file. You can link to specific packages instead using the `link` option:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [
      :ash,                          # inlined
      {:phoenix, link: :at},         # @deps/phoenix/usage-rules.md
      {:ecto, link: :markdown},      # [ecto usage rules](deps/ecto/usage-rules.md)
      {"phoenix:html", link: :at}    # @deps/phoenix/usage-rules/html.md
    ]
  ]
end
```

### Inline main rules, link sub-rules

If a package has many sub-rules and you want to keep the main rules inlined but link to sub-rules instead of inlining them all, use `main: false` to declare the same package twice with different options:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [
      {:ash, sub_rules: []},                                  # inline main rules only
      {:ash, sub_rules: :all, main: false, link: :markdown}   # link sub-rules only
    ]
  ]
end
```

The first entry inlines the main `usage-rules.md` with no sub-rules. The second entry adds all sub-rules as markdown links, with `main: false` preventing a duplicate main entry.

## Agent Skills

Skills are SKILL.md files that agent tools like Claude Code can discover and use. UsageRules can automatically generate skills from your dependencies' usage rules.

Generated skills use markers to delimit managed content. You can add custom content above the markers in any SKILL.md — it will be preserved across syncs.

### Auto-build skills from deps

The `deps` option auto-builds a `use-<package>` skill for each listed dependency:

```elixir
defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: :all,
    skills: [
      deps: [:ash, :req]
    ]
  ]
end
```

This generates `.claude/skills/use-ash/SKILL.md` and `.claude/skills/use-req/SKILL.md`, each with reference links to the package's usage rules, available mix tasks, doc search commands, and sub-rule references. Each package's `usage-rules.md` is written to a `references/<package>.md` file.

### Compose custom skills

The `build` option lets you compose a single skill from multiple packages:

```elixir
skills: [
  build: [
    "ash-framework": [
      description: "Expert on the Ash Framework ecosystem.",
      usage_rules: [:ash, :ash_postgres, :ash_phoenix, :ash_json_api]
    ]
  ]
]
```

This generates a single `.claude/skills/ash-framework/SKILL.md` with reference links to usage rules from all listed packages. Each package's rules are written to `references/<package>.md`. Regex is also supported:

```elixir
skills: [
  build: [
    "ash-framework": [
      description: "Expert on Ash.",
      usage_rules: [:ash, ~r/^ash_/]
    ]
  ]
]
```

### Stale skill cleanup

Skills generated by UsageRules include a `managed-by: usage-rules` marker in their YAML frontmatter. When a skill is removed from your config and you re-run `mix usage_rules.sync`, the stale skill files are automatically cleaned up. If you've added custom content to a managed skill, only the managed section is removed — your custom content is preserved.

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

### Pre-built skills

Packages can also ship pre-built skills that users can pull in directly. Place skill files in a `usage-rules/skills/` directory:

```
usage-rules/skills/
  my-skill/
    SKILL.md             # the skill definition
    references/
      some-ref.md        # optional reference files
```

Each `SKILL.md` is a standard skill file with YAML frontmatter:

```markdown
---
name: my-skill
description: "Use this skill when working with MyPackage."
---

## Overview

Content describing how to use the package effectively...
```

Users enable these by listing the package in `skills: [package_skills: [...]]` in their `mix.exs`. When synced, the skills are copied to the user's skills location with the `managed-by: usage-rules` marker injected automatically (enabling stale cleanup). Companion files (e.g. `references/`) are copied verbatim alongside the skill.

Make sure your `usage-rules/skills/` directory is included in your hex package's `files` option.

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
      usage_rules: :all
    ]
  ]
end
```

Then just run `mix usage_rules.sync` with no arguments.

### Migrating from v0.2

v1.0 removes `link_to_folder`, `link_style`, and `inline` options. Content is inlined by default. Use per-dep `link` option for linking:

```elixir
# Before (v0.2)
usage_rules: :all,
link_to_folder: "deps",
link_style: "at",
inline: ["usage_rules:all"]

# After (v1.0)
usage_rules: [
  {:ash, link: :at},
  {:phoenix, link: :at},
  "usage_rules:all"    # inlined by default
]
```
