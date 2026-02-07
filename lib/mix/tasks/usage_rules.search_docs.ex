# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.SearchDocs do
  use Mix.Task
  # This will eventually be replaced with something like `mix hex.docs.search` ideally

  @shortdoc "Searches hexdocs with human-readable output"

  @moduledoc """
  Searches hexdocs with human-readable output (markdown by default).
  If no version is specified, defaults to version used in the current mix project.
  If called outside of a mix project or the dependency is not used in the
  current mix project, defaults to the latest version.
  ## Search documentation for all dependencies in the current mix project
      $ mix usage_rules.search_docs "search term"
  ## Search documentation for specific packages
      $ mix usage_rules.search_docs "search term" -p ecto -p ash
  ## Search documentation for specific versions
      $ mix usage_rules.search_docs "search term" -p ecto@3.13.2 -p ash@3.5.26
  ## Control output format and pagination
      $ mix usage_rules.search_docs "search term" --output json --page 2 --per-page 20
  ## Search across all packages on hex
      $ mix usage_rules.search_docs "search term" --everywhere
  ## Search only in titles
      $ mix usage_rules.search_docs "search term" --query-by title
  ## Search in specific fields
      $ mix usage_rules.search_docs "search term" --query-by "doc,title,type"
  """

  @switches [
    package: :keep,
    page: :integer,
    per_page: :integer,
    output: :string,
    everywhere: :boolean,
    query_by: :string
  ]
  @aliases [p: :package, o: :output, e: :everywhere, q: :query_by]

  require Logger

  @impl true
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:req)
    {opts, args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Keyword.put(opts, :mix_project, !!Mix.Project.get())

    opts =
      if opts[:package] do
        Keyword.put(opts, :package, Keyword.get_values(opts, :package))
      else
        opts
      end

    term =
      case args do
        ["-" <> _ | _] -> raise_bad_args!()
        [] -> raise_bad_args!()
        [term | _args] -> term
      end

    filter_by =
      cond do
        opts[:everywhere] ->
          nil

        opts[:package] not in [nil, []] ->
          filter_from_packages(opts[:package])

        !Mix.Project.config()[:app] ->
          nil

        true ->
          filter_from_mix_lock()
      end

    query_params =
      %{
        q: term,
        query_by: opts[:query_by] || "doc,title",
        page: opts[:page] || 1,
        per_page: opts[:per_page] || 10
      }
      |> maybe_add_filter(filter_by)

    case Req.get("https://search.hexdocs.pm/", params: query_params) do
      {:ok, %{status: 200, body: body}} ->
        output_format = opts[:output] || "markdown"

        case output_format do
          "json" ->
            Mix.shell().info(Jason.encode!(body, pretty: true))

          "markdown" ->
            format_markdown_output(body, term, opts)

          _ ->
            Mix.raise("Invalid output format '#{output_format}'. Use 'json' or 'markdown'")
        end

      {:ok, %{status: status, body: body}} ->
        Mix.raise("HTTP error #{status} - #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Request failed\n\n#{inspect(reason)}")
    end
  end

  defp maybe_add_filter(query_params, nil), do: query_params
  defp maybe_add_filter(query_params, filter_by), do: Map.put(query_params, :filter_by, filter_by)

  defp format_markdown_output(body, term, opts) do
    %{
      "found" => total_found,
      "hits" => hits,
      "page" => current_page,
      "request_params" => %{"per_page" => per_page}
    } = body

    current_page = current_page || 1
    per_page = per_page || 10
    total_pages = ceil(total_found / per_page)

    # Build the full markdown content
    markdown_content =
      build_markdown_content(term, opts, total_found, current_page, total_pages, hits, per_page)

    # Output using appropriate method
    if tty?() do
      IO.ANSI.Docs.print(markdown_content, "text/markdown", [])
    else
      Mix.shell().info(markdown_content)
    end
  end

  defp build_markdown_content(term, opts, total_found, current_page, total_pages, hits, per_page) do
    # Header with help text at the top
    search_scope = if opts[:everywhere], do: " across all packages", else: ""

    header = """
    # Search Results for "#{term}"#{search_scope}

    Found #{total_found} results (page #{current_page} of #{total_pages})

    #{format_navigation_help_markdown(term, current_page, total_pages, opts)}

    #{format_search_scope_info(opts)}

    ---

    """

    # Results - reverse order in TTY for better readability
    results =
      hits
      |> if(tty?(), do: &Enum.reverse/1, else: &Function.identity/1).()
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {hit, index} ->
        # Adjust index calculation for reversed results
        actual_index = if tty?(), do: length(hits) - index + 1, else: index
        format_search_result_markdown(hit, actual_index, current_page, per_page)
      end)

    docs_hint =
      try do
        term
        |> Code.string_to_quoted!()
      rescue
        _ ->
          nil
      end
      |> IEx.Introspection.decompose(__ENV__)
      |> case do
        :error ->
          ""

        other ->
          show? =
            case other do
              {{:__aliases__, _, parts}, _} -> compiled?(parts)
              {:{}, [], [{:__aliases__, _, parts}, _, _]} -> compiled?(parts)
              {:__aliases__, _, parts} -> compiled?(parts)
              _ -> false
            end

          if show? do
            """
            For local docs, run:

                mix usage_rules.docs #{term}
            """
          else
            ""
          end
      end

    header <> results <> docs_hint
  end

  defp compiled?(parts) do
    parts
    |> Module.concat()
    |> Code.ensure_loaded?()
  end

  defp format_search_result_markdown(hit, index, current_page, per_page) do
    %{
      "document" => %{
        "title" => title,
        "package" => package,
        "type" => type,
        "ref" => ref
      },
      "highlights" => highlights
    } = hit

    # Calculate global result number
    global_index = (current_page - 1) * per_page + index

    # Convert <mark> tags to ANSI orange highlighting for TTY
    title_display = if tty?(), do: convert_mark_tags_to_ansi(title), else: title

    result = """
    ## #{global_index}. #{title_display}

    **Package:** #{package}
    **Type:** #{type}
    **Reference:** #{ref}

    """

    # Show highlighted snippets
    highlights_text =
      highlights
      # Limit to 2 highlights to avoid clutter
      |> Enum.take(2)
      |> Enum.map_join("\n\n", fn highlight ->
        snippet = highlight["snippet"]
        field = highlight["field"]

        # Convert <mark> tags to ANSI orange highlighting for TTY
        snippet_display = if tty?(), do: convert_mark_tags_to_ansi(snippet), else: snippet

        case field do
          "title" -> "**Title match:** #{snippet_display}"
          "doc" -> "**Content:** #{snippet_display}"
          _ -> "**#{String.capitalize(field)}:** #{snippet_display}"
        end
      end)

    footer = """

    **full docs:**
    https://hexdocs.pm/#{extract_package_name(package)}/#{ref}

    ---

    """

    result <> highlights_text <> footer
  end

  defp convert_mark_tags_to_ansi(text) do
    text
    # Orange color
    |> String.replace("<mark>", "\e[38;5;208m")
    # Reset color
    |> String.replace("</mark>", "\e[0m")
  end

  defp format_search_scope_info(opts) do
    cond do
      opts[:everywhere] ->
        "**Searching:** All packages on hex.pm"

      opts[:package] not in [nil, []] ->
        packages = opts[:package] |> Enum.join(", ")
        "**Searching:** #{packages}"

      !Mix.Project.config()[:app] ->
        "**Searching:** All packages on hex.pm"

      true ->
        "**Searching:** Dependencies from current mix project"
    end
  end

  defp format_navigation_help_markdown(term, current_page, total_pages, opts) do
    base_cmd = build_base_command(term, opts)

    navigation = []

    # Previous page
    navigation =
      if current_page > 1 do
        prev_cmd = "#{base_cmd} --page #{current_page - 1}"
        navigation ++ ["⬅️  **Previous page:** `#{prev_cmd}`"]
      else
        navigation
      end

    # Next page
    navigation =
      if current_page < total_pages do
        next_cmd = "#{base_cmd} --page #{current_page + 1}"
        navigation ++ ["- **Next page:** `#{next_cmd}`"]
      else
        navigation
      end

    # Jump to specific page
    navigation =
      if total_pages > 1 do
        jump_cmd = "#{base_cmd} --page <PAGE_NUMBER>"
        navigation ++ ["- **Jump to page:** `#{jump_cmd}`"]
      else
        navigation
      end

    if navigation != [] do
      "## Navigation\n\n" <> Enum.join(navigation, "\n") <> "\n\n"
    else
      ""
    end
  end

  defp build_base_command(term, opts) do
    base = "mix usage_rules.search_docs \"#{term}\""

    # Add flags
    flags = []

    # Add package filters
    packages = opts[:package] || []
    package_args = Enum.map(packages, &"-p #{&1}")
    flags = flags ++ package_args

    # Add everywhere flag
    flags =
      if opts[:everywhere] do
        flags ++ ["--everywhere"]
      else
        flags
      end

    if flags != [] do
      "#{base} #{Enum.join(flags, " ")}"
    else
      base
    end
  end

  defp extract_package_name(package_with_version) do
    package_with_version
    |> String.split("-")
    |> Enum.drop(-1)
    |> Enum.join("-")
  end

  defp filter_from_mix_lock do
    Mix.Task.run("compile")

    apps =
      if apps_paths = Mix.Project.apps_paths() do
        Enum.filter(Mix.Project.deps_apps(), &is_map_key(apps_paths, &1))
      else
        [Mix.Project.config()[:app]]
      end

    filter =
      apps
      |> Enum.flat_map(fn app ->
        Application.load(app)
        Application.spec(app, :applications)
      end)
      |> Enum.uniq()
      |> Enum.map_join(", ", fn app ->
        "#{app}-#{Application.spec(app, :vsn)}"
      end)

    "package:=[#{filter}]"
  end

  defp filter_from_packages(packages) do
    filter =
      packages
      |> Enum.flat_map(fn package ->
        case Req.get("https://hex.pm/api/packages/#{package}", []) do
          {:ok, %{status: 200, body: body}} ->
            ["#{package}-#{get_latest_version(body)}"]

          other ->
            Logger.warning(
              "Failed to get latest version for package #{package}: #{inspect(other)}"
            )

            []
        end
      end)
      |> Enum.join(", ")

    "package:=[#{filter}]"
  end

  defp get_latest_version(package) do
    versions =
      for release <- package["releases"],
          version = Version.parse!(release["version"]),
          # ignore pre-releases like release candidates, etc.
          version.pre == [] do
        version
      end

    Enum.max(versions, Version)
  end

  @doc false
  # assume we are not in a tty if we can't tell
  defp tty? do
    case :file.read_file_info("/dev/stdin") do
      {:ok, info} ->
        elem(info, 2) == :device

      _ ->
        false
    end
  rescue
    _ ->
      false
  end

  @spec raise_bad_args!() :: no_return()
  defp raise_bad_args! do
    Mix.raise("""
    Must provide a search term. For example:
        $ mix usage_rules.search_docs "search term"
    """)
  end
end
