# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.List do
  use Mix.Task

  @shortdoc "Lists usage-rules.md and sub-rules (usage-rules/*.md) for dependencies"

  @moduledoc """
  Prints each dependency that ships usage rules, and which sub-rule files exist.

  Sub-rules are the basenames of `deps/<app>/usage-rules/*.md` (excluding `skills/` trees),
  consistent with `mix usage_rules.sync`.

  Two errors can be raised normally. First is if the dependency is not in the project,
  then the "No dependency matching..." error will occur.
  The second error is if you have more than one argument. Only one dependency may be filtered at one time.

  ## Examples

      $ mix usage_rules.list

      $ mix usage_rules.list ash
  """

  @impl Mix.Task
  def run(argv) do
    {_opts, argv} = OptionParser.parse!(argv, strict: [])

    filter = package_filter(argv)
    pairs = discover_dep_pairs()

    pairs =
      case filter do
        nil ->
          pairs

        f ->
          found = Enum.filter(pairs, fn {dep, _} -> dep_matches?(dep, f) end)

          if found == [] do
            Mix.raise("No dependency matching #{inspect(f)} in this project")
          else
            found
          end
      end

    infos =
      pairs
      |> Enum.map(fn {dep, path} -> {dep, path, package_usage_rules_info(path)} end)
      |> Enum.filter(fn {_dep, _path, info} -> info.main? or info.subs != [] end)

    cond do
      infos == [] && filter ->
        Mix.shell().info("Dependency \"#{filter}\" has no usage-rules.md or usage-rules/*.md.")

      infos == [] ->
        Mix.shell().info(
          "No dependencies include usage rules (no usage-rules.md or usage-rules/*.md under deps/)."
        )

      true ->
        Mix.shell().info(format_report(infos))
    end

    Mix.shell().info(builtin_note())
  end

  defp package_filter([]), do: nil

  defp package_filter([one]) do
    one
    |> String.trim()
  end

  defp package_filter(_) do
    Mix.raise("mix usage_rules.list accepts at most one package name")
  end

  defp dep_matches?(dep, filter) do
    String.downcase(to_string(dep)) == String.downcase(filter)
  end

  defp discover_dep_pairs do
    top_level_deps =
      Mix.Project.get().project()[:deps] |> Enum.map(&elem(&1, 0))

    umbrella_deps =
      (Mix.Project.apps_paths() || [])
      |> Enum.flat_map(fn {app, path} ->
        Mix.Project.in_project(app, path, fn _ ->
          Mix.Project.get().project()[:deps] |> Enum.map(&elem(&1, 0))
        end)
      end)

    all_dep_names = Enum.uniq(top_level_deps ++ umbrella_deps)

    # Prefer the converger over `Mix.Project.deps_paths/0`: the deps cache can be
    # empty when another Mix project is still on the stack (e.g. an umbrella
    # app or tests using `Mix.Project.in_project/4`), which would hide path deps.
    Mix.Dep.Converger.converge(env: Mix.env(), target: Mix.target())
    |> Enum.filter(fn %{app: app} -> app in all_dep_names end)
    |> Enum.map(fn %{app: app, opts: opts} ->
      dest = Keyword.fetch!(opts, :dest)
      {app, Path.relative_to_cwd(dest)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp package_usage_rules_info(package_path) when is_binary(package_path) do
    main? = File.regular?(Path.join(package_path, "usage-rules.md"))
    subs = sub_rule_basenames(package_path)
    %{main?: main?, subs: subs}
  end

  defp sub_rule_basenames(package_path) do
    dir = Path.join(package_path, "usage-rules")

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 == "skills"))
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&Path.rootname/1)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  defp format_report(infos) do
    header = "Dependencies with usage rules:\n"

    body =
      Enum.map_join(infos, "\n", fn {dep, path, %{main?: main?, subs: subs}} ->
        [
          "  #{inspect(dep)}  (#{path})",
          "    usage-rules.md: " <> if(main?, do: "yes", else: "no"),
          "    sub-rules: " <> subs_line(subs)
        ]
        |> Enum.join("\n")
      end)

    header <> body
  end

  defp subs_line([]), do: "(none)"
  defp subs_line(subs), do: Enum.join(subs, ", ")

  defp builtin_note do
    """
    Built-in config atoms :elixir and :otp pull :usage_rules sub-rules \"elixir\" and \"otp\" (see mix usage_rules.sync docs).
    """
    |> String.trim_trailing()
  end
end
