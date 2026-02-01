# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

[
  ## all available options with default values (see `mix check` docs for description)
  # parallel: true,
  # skipped: true,

  ## list of tools (see `mix check` docs for defaults)
  tools: [
    {:doctor, false},
    {:reuse, command: ["pipx", "run", "reuse", "lint", "-q"]}
  ]
]
