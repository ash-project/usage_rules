<!--
SPDX-FileCopyrightText: 2025 Zach Daniel
SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## v1.0.1 (2026-02-10)




### Improvements:

* regexes in usage rule deps, add examples by Zach Daniel

## v1.0.0-rc.3 (2026-02-10)




### Improvements:

* use refernece files for all usage rules by Zach Daniel

## v1.0.0-rc.2 (2026-02-07)




### Improvements:

* reference mode for skill deps by Zach Daniel

## v1.0.0-rc.1 (2026-02-07)




### Improvements:

* make package inlining configured per-dep, clean ups by Zach Daniel

## v1.0.0-rc.0 (2026-02-07)
### Breaking Changes:

* rebuild usage rules to be config-driven and support agent skills by Zach Daniel



## v0.1.26 (2025-11-05)




### Bug Fixes:

* Include rules from all apps in umbrella project (#37) by Nathan Alderson

## v0.1.25 (2025-10-14)




### Bug Fixes:

* use AGENTS.md consistently in task help (#28) by Lars Wikman

### Improvements:

* Impl `supports_umbrella?` (#33) by Wigny

* Add ability to extract one or more usage rules to folder without modifying any files. (#29) by olivermt

## v0.1.24 (2025-08-31)




### Bug Fixes:

* typo in OTP usage rules (#22) by Hubert Pompecki

### Improvements:

* Add warning about %{} pattern matching (#23) by jlgeering

## v0.1.23 (2025-07-22)




### Bug Fixes:

* trim trailing application descriptions by Zach Daniel

## v0.1.22 (2025-07-19)




### Bug Fixes:

* make igniter not an optional dependency, but a normal one by Zach Daniel

### Improvements:

* show `mix help test` in testing usage rules by Zach Daniel

* add a debugging header to elixir usage rules by Zach Daniel

## v0.1.21 (2025-07-17)




### Improvements:

* only show notice about local docs when module is compiled by Zach Daniel

## v0.1.20 (2025-07-17)




### Improvements:

* add `mix usage_rules.docs` by Zach Daniel

## v0.1.19 (2025-07-17)




### Improvements:

* add --query-by option to mix task by Zach Daniel

## v0.1.18 (2025-07-17)




### Improvements:

* add `usage_rules.search_docs` task by Zach Daniel

* instruct agents to use the new task by Zach Daniel

* explain about no early returns in usage rules by Zach Daniel

* add a note on early returns not being a thing in usage-rules.md by Zach Daniel

## v0.1.17 (2025-07-17)




### Improvements:

* replace auto-sync with notice (#12) by andyl

## v0.1.16 (2025-07-10)




## v0.1.15 (2025-07-02)




### Improvements:

* support sub-rules, in a usage-rules folder by Zach Daniel

* remove --builtins option

* add --remove-missing option by Zach Daniel

* add notice when using --all about the dangers of it by Zach Daniel

* update usage rules for Elixir by Zach Daniel

## [Unreleased]

### Features:

* add sub-rules support - Packages can now have a `usage_rules/` folder with multiple sub-rule files that can be included individually using `package:rule` syntax or all at once with `package:all`
* add `--inline` option - Force specific packages to be inlined even when using `--link-to-folder`. Supports special `usage_rules:all` spec to inline all sub-rules while linking main packages

## v0.1.14 (2025-06-26)




### Improvements:

* update installer by Zach Daniel

## v0.1.13 (2025-06-26)




### Improvements:

* trim testing usage rules by Zach Daniel

## v0.1.12 (2025-06-25)




### Improvements:

* add testing usage rules by Zach Daniel

## v0.1.11 (2025-06-25)




### Improvements:

* add descriptions to usage rules by Zach Daniel

* make builtin usage rules always show inline by Zach Daniel

## v0.1.10 (2025-06-25)




### Improvements:

* guard against excessive macro usage in elixir rules by Zach Daniel

## v0.1.9 (2025-06-24)




### Bug Fixes:

* don't mention hd/1 or tl/1 in elixir usage rules by Zach Daniel

## v0.1.8 (2025-06-24)




### Improvements:

* remove a confusing usage rule on list purposes by Zach Daniel

* add a usage rule about indexing lists/enumerables by Zach Daniel

* add builtin usage rules by Zach Daniel

## v0.1.7 (2025-06-23)




### Bug Fixes:

* usage proper markdown comments by Zach Daniel

## v0.1.6 (2025-06-06)




### Improvements:

* add `--link-to-folder deps` option, and recommend its use

## v0.1.5 (2025-06-06)




### Improvements:

* use markdown links by default, allow opting in to `--link-style at`

## v0.1.4 (2025-06-06)




### Improvements:

* add `--link-to-folder` option

## v0.1.3 (2025-05-24)




### Bug Fixes:

* update package url in docs & hex

## v0.1.2 (2025-05-24)




### Bug Fixes:

* replace package-rules with usage-rules

## v0.1.1 (2025-05-24)




### Improvements:

* only suggest top-level deps

## v0.1.0 (2025-05-24)




### Bug Fixes:

* bugs w/ duplicating content

### Improvements:

* add `--remove` option

* port initial feature set over and test it
