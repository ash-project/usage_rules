# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

if Mix.env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    types: [types: [tidbit: [hidden?: true], important: [header: "Important Changes"]]],
    version_tag_prefix: "v",
    manage_mix_version?: true,
    manage_readme_version: true
end
