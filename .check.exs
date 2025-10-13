# SPDX-FileCopyrightText: 2025 Zach Daniel
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
