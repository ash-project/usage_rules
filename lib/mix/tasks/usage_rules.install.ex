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
        `usage_rules` is installed!

        Example sync commands:
        - `mix usage_rules.sync AGENTS.md --all --link-to-folder rules --inline usage_rules:all`
        - `mix usage_rules.sync RULES.md --all`

        For more info and examples: `mix help usage_rules.sync`
        """)
    end
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
