# SPDX-FileCopyrightText: 2025 Zach Daniel
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
      Usage Rules: Sync usage rules for the packages you use.

      Suggested starting point to sync all usage rules:

          mix usage_rules.sync AGENTS.md --all \\
            --inline usage_rules:all \\
            --link-to-folder deps

      Or sync only a specific set, copying their rules to a
      specific folder

          mix usage_rules.sync AGENTS.md \\
            ash ash_postgres \\
            --link-to-folder rules


      For more info and examples: `mix help usage_rules.sync`
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
