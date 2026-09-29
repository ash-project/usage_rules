# SPDX-FileCopyrightText: 2026 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.Validate do
  use Mix.Task

  @shortdoc "Validates references in usage-rules-managed files"

  @moduledoc """
  Validates module, function, and file references found in the
  files generated and managed by `mix usage_rules.sync`, using ex_doc's own
  autolink pipeline. Warnings are ex_doc's own, printed with file/line
  information — the same warnings a HexDocs build would emit over the same
  content. See `UsageRules.Validator` for exactly what is and is not
  checked.

  ex_doc must be compiled and available. It is already a dev dependency of
  most Hex packages; when it is missing, the task fails with an actionable
  error telling you how to add it.

  By default, only rules-managed files are validated:

    * the composed file from the `:file` option of your `:usage_rules` config
      (e.g. `AGENTS.md`)
    * `*.md` files under skills managed by usage-rules (skills whose
      `SKILL.md` contains `managed-by: usage-rules`)

  Explicit file paths can also be given to validate those instead.

  ## Examples

      $ mix usage_rules.validate
      $ mix usage_rules.validate AGENTS.md usage-rules.md

  ## Exit status

  Exits with a nonzero status when ex_doc emits any warning, making the task
  suitable for CI.
  """

  @switches [help: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, files, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}\n\n#{usage()}")
    end

    if opts[:help] do
      Mix.shell().info(usage())
    else
      validate(files)
    end
  end

  defp validate(files) do
    unless Mix.Project.get() do
      Mix.raise("mix usage_rules.validate must be run inside a Mix project")
    end

    files =
      case files do
        [] -> managed_files()
        files -> files
      end

    if files == [] do
      Mix.shell().info(no_files_message())
    else
      result = UsageRules.Validator.validate(files)

      Mix.shell().info(
        "Validated #{length(result.files)} file(s) with ex_doc; " <>
          if(result.warned?, do: "warnings were emitted.", else: "no warnings.")
      )

      if result.warned? do
        exit({:shutdown, 1})
      end
    end
  end

  defp managed_files do
    config = Mix.Project.config()[:usage_rules] || []
    composed_file(config) ++ managed_skill_files(Keyword.get(config, :skills) || [])
  end

  defp composed_file(config) do
    case Keyword.get(config, :file) do
      nil -> []
      file -> if File.regular?(file), do: [file], else: []
    end
  end

  defp managed_skill_files(skills_config) do
    location = Keyword.get(skills_config, :location, ".claude/skills")

    Path.wildcard(Path.join(location, "*/SKILL.md"))
    |> Enum.filter(&String.contains?(File.read!(&1), "managed-by: usage-rules"))
    |> Enum.flat_map(fn skill_md ->
      skill_md
      |> Path.dirname()
      |> then(&Path.wildcard(Path.join(&1, "**/*.md")))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp no_files_message do
    """
    No usage-rules-managed files found to validate.

    Add a :usage_rules config to your mix.exs and run `mix usage_rules.sync`,
    or pass file paths to validate.
    """
    |> String.trim_trailing()
  end

  defp usage do
    """
    mix usage_rules.validate [files...]

    Validates module, function, and file references in
    usage-rules-managed files (or the given files) with ex_doc's own
    autolink pipeline. Exits nonzero when ex_doc emits any warning.
    """
  end
end
