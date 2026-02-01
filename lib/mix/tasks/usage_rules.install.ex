# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Installs usage_rules"
  end

  @spec example() :: String.t()
  def example do
    "mix igniter.install usage_rules"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    ## Example

    ```sh
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.UsageRules.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :usage_rules,
        example: __MODULE__.Docs.example(),
        only: [:dev]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.add_notice("""
      UsageRules: Manage your AGENTS.md file and agent skills from dependencies.

      Add configuration to your mix.exs project/0.:

          def project do
            [
              usage_rules: usage_rules()
            ]
          end

          defp usage_rules do
            # Example for those using claude.
            [
              file: "CLAUDE.md",
              # rules to include directly in CLAUDE.md
              usage_rules: ["usage_rules:all"],
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

      Then run:

          mix usage_rules.sync

      For more info: `mix help usage_rules.sync`
      """)
    end

    @impl Igniter.Mix.Task
    def supports_umbrella?, do: true
  end
else
  defmodule Mix.Tasks.UsageRules.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'usage_rules.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
