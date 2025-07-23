# UsageRules

**UsageRules** is a development tool for Elixir projects that:

- helps gather and consolidate usage rules from dependencies to provide to LLM agents via `mix usage_rules.sync`
- provides pre-built usage rules for Elixir
- provides a powerful documentation search task for hexdocs with `mix usage_rules.search_docs`

## Quickstart

```sh
# install usage_rules into your project
mix igniter.install usage_rules

# swap AGENTS.md out for any file you like, e.g `CLAUDE.md`
# sync projects as links to their usage rules
# to save tokens. Agent can view them on demand.
# Existing rules in the file are retained.
mix usage_rules.sync AGENTS.md --all \
  --inline usage_rules:all \
  --link-to-folder deps
```

## Does it help?

Yes, and we have data to back it up: https://github.com/ash-project/evals/blob/main/reports/flagship.md

You'll note this package itself doesn't have a usage-rules.md. Its a simple tool that likely would not benefit from having a usage-rules.md file.

`usage-rules.md` is not an existing standard, rather it is a community initiative that may evolve over time as adoption grows and feedback is gathered. We encourage experimentation and welcome input on how to make this approach more useful for the broader Elixir ecosystem.

## For Package Authors

Even if you don't want to use LLMs, its very possible that your users will, and they will often come to you with hallucinations from their LLMs and try to get your help with it. Writing a `usage-rules.md` file is a great way to stop this sort of thing 😁

We don't really know what makes great usage-rules.md files yet. Ash Framework is experimenting with quite fleshed out usage rules which seems to be working quite well. See [Ash Framework's usage-rules.md](https://github.com/ash-project/ash/blob/main/usage-rules.md) for one such large example. Perhaps for your package or framework only a few lines are necessary. We will all have to adjust over time.

One quick tip is to have an agent begin the work of writing rules for you, by pointing it at your docs and asking it to write a `usage-rules.md` file in a condensed format that would be useful for agents to work with your tool. Then, aggressively prune and edit it to your taste.

Make sure that your `usage-rules.md` file is included in your hex package's `files` option, so that it is distributed with your package.

### Sub rules

A package can have a `package-rules.md` and/or sub-rule files, each of which is referred to separately.
For example:

```
package-rules.md # general rules
package-rules/
  html.md # html specific rules
  database.md # database specific rules
```

When synchronizing, these are stated separately, like so:

```
mix usage_rules.sync AGENTS.md package package:html package:database
```

## Key Features

1. **Dependency Rules Collection**: Automatically discovers and collects usage rules from dependencies that provide `usage-rules.md` files in their package directory
2. **Rules Consolidation**: Combines multiple package rules into a single file with proper sectioning and markers
3. **Status Tracking**: Can list dependencies with usage rules and check if your consolidated file is up-to-date
4. **Selective Management**: Allows adding/removing specific packages from your rules file
5. **Documentation Search**: Search hexdocs with human-readable markdown output using `mix usage_rules.search_docs` - designed to help AI agents find relevant documentation

## How It Works

1. The tool scans your project's dependencies (in `deps/` directory)
2. Looks for `usage-rules.md` files in each dependency
3. Consolidates these rules into a target file with special markers like `<-- package-name-start -->` and `<-- package-name-end -->`
4. Maintains sections that can be updated independently as dependencies change

This is particularly useful for projects using frameworks like Ash, Phoenix, or other packages that provide specific usage guidelines, coding patterns, or best practices that should be followed consistently across your project.

## Usage

The main task `mix usage_rules.sync` provides several modes of operation:

### Standard usage (recommended)

There are two standard ways to use usage_rules. The first, is to copy usage rules into your project. This allows customization and visibility into the rules. The second is to use the rules files directly from the deps in your `deps/` folder. In both cases, your rules file is modified to link to the usage rules files, as a breadcrumb to the agent.

#### Copying into your project

This will create a folder called `rules`, with a file per package that has a `usage-rules.md` file. Then it will link
to those from you rules file.

```sh
mix usage_rules.sync AGENTS.md --all \
  --link-to-folder deps \
  --inline usage_rules:all
```

#### Using deps folder

This will add a section in your rules file for each of your top level dependencies that have a `usage-rules.md`. It is
simply a breadcrumb to tell the agent that it should look
in `deps/<package-name>/usage-rules.md` when working with
that package. This will not overwrite your existing rules, but will append to it, and future calls will synchronize those contents.

```sh
mix usage_rules.sync CLAUDE.md --all --link-to-folder deps
```

### Combine specific packages
```sh
mix usage_rules.sync rules.md ash phoenix
```

### Gather all dependencies with usage rules
```sh
mix usage_rules.sync CLAUDE.md --all
```

### List available packages with usage rules
```sh
mix usage_rules.sync --list
```

### Check status against a file
```sh
mix usage_rules.sync CLAUDE.md --list
```

### Remove packages from a file
```sh
mix usage_rules.sync CLAUDE.md ash --remove
```

### Use folder links for better organization
```sh
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder rules
```

### Use @-style folder links
```sh
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder rules --link-style at
```

### Link directly to deps files
```sh
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder deps
```

### Gather all dependencies with folder links
```sh
mix usage_rules.sync CLAUDE.md --all --link-to-folder docs
```

### Documentation Search (`mix usage_rules.search_docs`)

The `mix usage_rules.search_docs` task searches hexdocs with human-readable markdown output, specifically designed to help AI agents find relevant documentation.

```sh
# Search documentation for all dependencies in the current mix project
mix usage_rules.search_docs "search term"

# Search documentation for specific packages 
mix usage_rules.search_docs "search term" -p ecto -p ash

# Search documentation for specific versions 
mix usage_rules.search_docs "search term" -p ecto@3.13.2 -p ash@3.5.26

# Control output format and pagination
mix usage_rules.search_docs "search term" --output json --page 2 --per-page 20

# Search across all packages on hex
mix usage_rules.search_docs "search term" --everywhere

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title

# Search in specific fields (available: doc, title, type)
mix usage_rules.search_docs "validation" --query-by "doc,title"
```

## Advanced Features

### Folder Links (`--link-to-folder`)

Organizes usage rules into separate files for better management of large rule sets.

**Options:**
- `--link-style markdown` (default): `[ash usage rules](docs/ash.md)`
- `--link-style at`: `@docs/ash.md` (optimized for Claude AI)
- `--link-to-folder deps`: Links directly to `deps/package/usage-rules.md` (no file copying)

**Examples:**
```sh
# Create individual files with markdown links
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder docs

# Use @-style links for Claude AI
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder docs --link-style at

# Link directly to deps without copying
mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder deps
```

## Installation

### With Igniter

`mix igniter.install usage_rules`.

Add the dependency manually

```elixir
def deps do
  [
    # should only ever be used as a dev dependency
    # requires igniter as a dev dependency
    {:usage_rules, "~> 0.1", only: [:dev]},
    {:igniter, "~> 0.6", only: [:dev]}
  ]
end
```
