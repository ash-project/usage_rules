# SPDX-FileCopyrightText: 2026 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule UsageRules.Validator do
  @moduledoc """
  Validates documentation references in usage-rules-managed markdown files
  by driving ex_doc's own autolink pipeline over them.

  This is the engine behind `mix usage_rules.validate`. Each file is parsed
  and autolinked exactly like an extra page in a docs build — through ex_doc's
  extras builder and its formatter autolink pass — and the warnings are
  ex_doc's own, printed with file/line information: the same warnings you
  would get from a HexDocs build over the same content.

  ## What ex_doc checks

    * function references with arity in inline code spans
      (`Module.function/arity`, `:erlang.function/arity`) — including
      `@doc false` / `@moduledoc false` targets, which are reported as
      "hidden or private"
    * hidden modules mentioned in inline code spans
    * explicit reference links in backtick form: `` [`Mod`](\`Mod\`) `` and
      `` [`mix task`](\`mix task\`) ``
    * relative file links between the validated files (links to files that
      are not part of the validated set do not resolve and are reported)

  ## What ex_doc does not check

  ex_doc deliberately skips fenced code blocks when autolinking, and it
  stays silent about plain code span mentions that never resolve, such as
  `mix task` names and bare undefined module names — the same silence you
  get inside moduledocs. Validation warnings are exactly a docs build's
  warnings, nothing more and nothing less.

  ex_doc must be compiled and available. When it is not, validation fails
  with an actionable error (see `ensure_ex_doc!/1`).
  """

  @doc """
  Ensures the ex_doc machinery is compiled and running, or fails with an
  actionable error.

  `validate/1` resolves references with ex_doc, so it must be compiled and
  available. ex_doc is already a dev dependency of most Hex packages; when
  it is missing, add it to your `mix.exs` and compile it.

  The loader (defaults to `Code.ensure_loaded/1`) is injectable so tests can
  exercise the failure path.
  """
  @spec ensure_ex_doc!((module() -> {:module, module()} | {:error, term()})) :: :ok
  def ensure_ex_doc!(loader \\ &Code.ensure_loaded/1) do
    with {:module, _} <- loader.(ExDoc.Formatter),
         true <- markdown_processor_available?(),
         {:ok, _} <- Application.ensure_all_started(:ex_doc) do
      :ok
    else
      false ->
        Mix.raise(ex_doc_unavailable_message(:earmark_parser_unavailable))

      {:error, reason} ->
        Mix.raise(ex_doc_unavailable_message(reason))
    end
  end

  @doc false
  def ex_doc_unavailable_message(reason) do
    """
    reference validation requires ex_doc, but it is not compiled and available \
    (reason: #{inspect(reason)}).

    ex_doc provides the reference resolution engine used to validate
    documentation references. Most Hex packages already depend on it as a dev
    dependency; make sure it is declared in your mix.exs and compiled:

        defp deps do
          [
            {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false}
          ]
        end

        $ mix deps.get && mix deps.compile
    """
    |> String.trim_trailing()
  end

  @doc """
  Validates the given markdown files (paths on disk) with ex_doc's own
  autolink pipeline.

  ex_doc's warnings are printed to stderr as they are found, in ex_doc's own
  format with file/line information. Returns:

      %{files: [path], warned?: boolean()}

  `warned?` is true when ex_doc emitted at least one warning, which callers
  should treat as validation failure.
  """
  @spec validate([Path.t()]) :: %{files: [Path.t()], warned?: boolean()}

  # Everything that touches ex_doc modules is compiled only when ex_doc is
  # available, so projects that use usage_rules as a dev dependency without
  # ex_doc compiled still compile this module cleanly. Calling validate/1
  # there fails fast with the actionable error from ensure_ex_doc!/1.
  if Code.ensure_loaded?(ExDoc) do
    # The flag `ExDoc.warn/2` sets whenever it emits a warning. ex_doc's own
    # CLI uses it (via `ExDoc.generate_docs/4`'s `warned?` result) to decide
    # the exit status of docs builds; we read the same flag after running
    # ex_doc's autolink phase.
    @warned_flag {ExDoc, :warned?}

    def validate(files) when is_list(files) do
      ensure_ex_doc!()

      :persistent_term.erase(@warned_flag)

      # The flag key is read and erased the same way ex_doc's own CLI decides
      # the docs build exit status.
      extras = ExDoc.Extras.build(files, %ExDoc.Config{})

      formatter_config = %ExDoc.Formatter.Config{apps: project_apps(), deps: []}

      ExDoc.Formatter.autolink(formatter_config, [], [], extras, extension: ".html")

      %{files: files, warned?: :persistent_term.get(@warned_flag, false)}
    end

    defp markdown_processor_available?, do: ExDoc.Markdown.Earmark.available?()

    defp project_apps do
      case Mix.Project.get() do
        nil ->
          []

        _project ->
          umbrella_apps = Map.keys(Mix.Project.apps_paths() || %{})

          ([Mix.Project.config()[:app]] ++ umbrella_apps)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
      end
    end
  else
    def validate(_files) do
      ensure_ex_doc!()
    end

    defp markdown_processor_available?, do: false
  end
end
