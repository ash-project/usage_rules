# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.Sync.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Sync AGENTS.md and agent skills from project config"
  end

  @spec example() :: String.t()
  def example do
    "mix usage_rules.sync"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    Reads the `:usage_rules` key from your project config in `mix.exs` and generates
    an AGENTS.md file with usage rules from your dependencies, optionally generating
    agent skills as well.

    ## Configuration

    Add to your `mix.exs` project config:

    ```elixir
    #{code_sample()}
    ```

    Then run:
    ```sh
    #{example()}
    ```

    The config is the source of truth — packages present in the file but absent
    from config are automatically removed on each sync.
    """
  end

  def code_sample(spaces \\ 0) do
    """
    def project do
      [
        ...
        usage_rules: usage_rules()
      ]
    end

    defp usage_rules do
      # Example for those using claude.
      [
        file: "CLAUDE.md",
        # rules to include directly in CLAUDE.md
        # use a regex to match multiple deps, or atoms/strings for specific ones
        usage_rules: [:usage_rules, :ash, ~r/^ash_/],
        # If your CLAUDE.md is getting too big, link instead of inlining:
        usage_rules: [:usage_rules, :ash, {~r/^ash_/, link: :markdown}],
        # or use skills
        skills: [
          location: ".claude/skills",
          # Pull in pre-built skills shipped directly by packages
          package_skills: [:ash, ~r/^ash_/],
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
    """
    |> String.split("\n")
    |> Enum.map_join("\n", &String.pad_leading(&1, String.length(&1) + spaces))
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.UsageRules.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @managed_by_marker "usage-rules"

    @impl Mix.Task
    def run(argv) do
      {_opts, remaining, invalid} =
        OptionParser.parse(argv, strict: Igniter.Mix.Task.Info.global_options()[:switches])

      if Enum.any?(remaining ++ invalid) do
        Mix.raise("""
        WARNING: `mix usage_rules.sync` does not accept task-specific arguments.
        Configuration is now done in your `mix.exs` project config:

        #{__MODULE__.Docs.code_sample(4)}

        Then simply run: mix usage_rules.sync

        Only Igniter global flags are accepted (e.g. --yes, --dry-run, --check, --verbose).

        Run `mix help usage_rules.sync` for full configuration options.
        """)
      else
        super(argv)
      end
    end

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :usage_rules,
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter =
        if is_nil(igniter.parent) do
          igniter
          |> Igniter.assign(:prompt_on_git_changes?, false)
          |> Igniter.assign(:quiet_on_no_changes?, true)
        else
          igniter
        end

      config = read_config(igniter)

      case validate_config(config) do
        :ok ->
          skills_location = get_in(config, [:skills, :location]) || ".claude/skills"

          igniter
          |> include_dep_sources()
          |> Igniter.include_glob(Path.join(skills_location, "*/SKILL.md"))
          |> Igniter.include_glob(Path.join(skills_location, "*/**/*"))
          |> sync(config)

        {:error, message} ->
          Igniter.add_issue(igniter, message)
      end
    end

    @impl Igniter.Mix.Task
    def supports_umbrella?, do: true

    # -------------------------------------------------------------------
    # Config reading & validation
    # -------------------------------------------------------------------

    defp read_config(igniter) do
      if igniter.assigns[:test_mode?] do
        igniter.assigns[:usage_rules_config] || []
      else
        Mix.Project.config()[:usage_rules] || []
      end
    end

    defp validate_config(config) do
      cond do
        !Keyword.keyword?(config) ->
          {:error, "usage_rules config must be a keyword list"}

        is_nil(config[:file]) && is_nil(config[:usage_rules]) && is_nil(config[:skills]) ->
          {:error,
           """
           No usage_rules config found. Add to your mix.exs project config:

           #{__MODULE__.Docs.code_sample(4)}
           """}

        (link_error = validate_link_options(config[:usage_rules])) != nil ->
          {:error, link_error}

        true ->
          :ok
      end
    end

    defp validate_link_options(nil), do: nil
    defp validate_link_options(:all), do: nil

    defp validate_link_options({:all, opts}) when is_list(opts), do: validate_link_option(opts)

    defp validate_link_options(specs) when is_list(specs) do
      Enum.find_value(specs, fn
        {_inner, opts} when is_list(opts) -> validate_link_option(opts)
        _ -> nil
      end)
    end

    defp validate_link_option(opts) do
      case opts[:link] do
        nil -> nil
        style when style in [:at, :markdown] -> nil
        other -> "usage_rules link must be :at or :markdown, got: #{inspect(other)}"
      end
    end

    defp include_dep_sources(igniter) do
      igniter
      |> Igniter.include_glob("deps/*/usage-rules.md")
      |> Igniter.include_glob("deps/*/usage-rules/*.md")
      |> Igniter.include_glob("deps/*/usage-rules/skills/*/SKILL.md")
      |> Igniter.include_glob("deps/*/usage-rules/skills/*/**/*")
    end

    # -------------------------------------------------------------------
    # Main sync orchestration
    # -------------------------------------------------------------------

    defp sync(igniter, config) do
      all_deps = discover_deps(igniter)

      file = config[:file]
      usage_rules_config = config[:usage_rules]
      skills_config = config[:skills] || []

      # Resolve usage rules packages
      {package_rules, errors} = resolve_usage_rules(igniter, all_deps, usage_rules_config)

      # Report any resolution errors as issues
      igniter =
        Enum.reduce(errors, igniter, fn error, acc ->
          Igniter.add_issue(acc, error)
        end)

      # Generate AGENTS.md if file is configured and there are packages to sync,
      # or clean up old usage-rules section if the file exists but has no packages
      igniter =
        cond do
          file && !Enum.any?(errors) && Enum.any?(package_rules) ->
            generate_usage_rules(igniter, file, package_rules)

          file && Igniter.exists?(igniter, file) ->
            cleanup_stale_usage_rules_section(igniter, file)

          true ->
            igniter
        end

      skills_location = skills_config[:location] || ".claude/skills"

      # Expand deps into build specs (shorthand for single-package skills)
      package_build_specs =
        (skills_config[:deps] || [])
        |> expand_dep_specs(all_deps)
        |> Enum.filter(fn {_name, path, _mode} ->
          Igniter.exists?(igniter, Path.join(path, "usage-rules.md"))
        end)
        |> Enum.map(fn {pkg_name, _path, _mode} ->
          {:"use-#{pkg_name}", [usage_rules: [pkg_name]]}
        end)

      # Merge explicit build specs on top of package-derived ones
      build_specs = package_build_specs ++ (skills_config[:build] || [])
      build_names = Enum.map(build_specs, fn {name, _opts} -> to_string(name) end)

      # Discover package-provided skill names for stale cleanup
      package_skills_specs = skills_config[:package_skills] || []

      package_skill_names =
        discover_package_skill_names(igniter, all_deps, package_skills_specs)

      igniter =
        remove_stale_managed_skills(
          igniter,
          skills_location,
          build_names ++ package_skill_names
        )

      igniter =
        if Enum.any?(build_specs) do
          build_custom_skills(igniter, all_deps, build_specs, skills_location)
        else
          igniter
        end

      igniter =
        if Enum.any?(package_skills_specs) do
          sync_package_skills(igniter, all_deps, package_skills_specs, skills_location)
        else
          igniter
        end

      igniter
    end

    # -------------------------------------------------------------------
    # Dependency discovery
    # -------------------------------------------------------------------

    defp discover_deps(igniter) do
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

      mix_deps =
        Mix.Project.deps_paths()
        |> Enum.filter(fn {dep, _path} -> dep in all_dep_names end)
        |> Enum.map(fn {dep, path} -> {dep, Path.relative_to_cwd(path)} end)

      igniter_deps = get_deps_from_igniter(igniter)
      (mix_deps ++ igniter_deps) |> Enum.uniq() |> Enum.sort_by(&elem(&1, 0))
    end

    defp get_deps_from_igniter(igniter) do
      if igniter.assigns[:test_mode?] do
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.match?(path, ~r|^deps/[^/]+/usage-rules\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/usage-rules/[^/]+\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/usage-rules/skills/[^/]+/SKILL\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/usage-rules/skills/[^/]+/.+$|)
        end)
        |> Enum.map(fn {path, _source} ->
          package_name =
            path |> String.split("/") |> Enum.at(1) |> String.to_atom()

          {package_name, Path.join("deps", to_string(package_name))}
        end)
        |> Enum.uniq()
      else
        []
      end
    end

    defp get_packages_with_usage_rules(igniter, all_deps) do
      Enum.filter(all_deps, fn
        {_name, path} when is_binary(path) and path != "" ->
          Igniter.exists?(igniter, Path.join(path, "usage-rules.md")) ||
            Igniter.exists?(igniter, Path.join(path, "usage-rules"))

        _ ->
          false
      end)
    end

    # -------------------------------------------------------------------
    # Config resolution
    # -------------------------------------------------------------------

    defp resolve_usage_rules(_igniter, _all_deps, nil), do: {[], []}

    defp resolve_usage_rules(igniter, all_deps, :all),
      do: resolve_usage_rules(igniter, all_deps, {:all, []})

    defp resolve_usage_rules(igniter, all_deps, {:all, opts}) when is_list(opts) do
      rules =
        get_packages_with_usage_rules(igniter, all_deps)
        |> Enum.flat_map(fn {package_name, package_path} ->
          main_rules =
            if Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
              [{package_name, package_path, nil, opts}]
            else
              []
            end

          sub_rules =
            find_available_sub_rules(igniter, package_path)
            |> Enum.map(fn sub_rule_name ->
              {package_name, package_path, sub_rule_name, opts}
            end)

          main_rules ++ sub_rules
        end)

      {rules, []}
    end

    defp resolve_usage_rules(igniter, all_deps, specs) when is_list(specs) do
      {rules, errors} =
        Enum.reduce(specs, {[], []}, fn spec, {rules_acc, errors_acc} ->
          case extract_regex_spec(spec) do
            {%Regex{} = regex, opts} ->
              resolve_regex_usage_rules(igniter, all_deps, regex, opts, rules_acc, errors_acc)

            nil ->
              {package_name, opts} = parse_spec(spec)

              resolve_named_usage_rules(
                igniter,
                all_deps,
                package_name,
                opts,
                rules_acc,
                errors_acc
              )
          end
        end)

      {rules, errors}
    end

    defp extract_regex_spec(%Regex{} = regex), do: {regex, []}
    defp extract_regex_spec({%Regex{} = regex, opts}) when is_list(opts), do: {regex, opts}
    defp extract_regex_spec(_), do: nil

    defp resolve_regex_usage_rules(igniter, all_deps, regex, opts, rules_acc, errors_acc) do
      sub_rules_opt = opts[:sub_rules] || :all

      found =
        all_deps
        |> Enum.filter(fn {name, _path} -> Regex.match?(regex, to_string(name)) end)
        |> Enum.flat_map(fn {package_name, package_path} ->
          main =
            if opts[:main] != false &&
                 Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
              [{package_name, package_path, nil, opts}]
            else
              []
            end

          subs =
            case sub_rules_opt do
              :all ->
                find_available_sub_rules(igniter, package_path)
                |> Enum.map(fn sr -> {package_name, package_path, sr, opts} end)

              list when is_list(list) ->
                Enum.flat_map(list, fn sr ->
                  sub_path = Path.join([package_path, "usage-rules", "#{sr}.md"])

                  if Igniter.exists?(igniter, sub_path) do
                    [{package_name, package_path, sr, opts}]
                  else
                    []
                  end
                end)
            end

          main ++ subs
        end)

      {rules_acc ++ found, errors_acc}
    end

    defp resolve_named_usage_rules(
           igniter,
           all_deps,
           package_name,
           opts,
           rules_acc,
           errors_acc
         ) do
      case Enum.find(all_deps, fn {name, _path} -> name == package_name end) do
        {_name, package_path} ->
          sub_rules_opt = opts[:sub_rules] || :all

          main =
            if opts[:main] != false &&
                 Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
              [{package_name, package_path, nil, opts}]
            else
              []
            end

          case sub_rules_opt do
            :all ->
              subs =
                find_available_sub_rules(igniter, package_path)
                |> Enum.map(fn sr -> {package_name, package_path, sr, opts} end)

              found = main ++ subs

              if Enum.any?(found) do
                {rules_acc ++ found, errors_acc}
              else
                {rules_acc,
                 errors_acc ++
                   [
                     "Package :#{package_name} is a dependency but does not have a usage-rules.md file or sub-rules in usage-rules/"
                   ]}
              end

            list when is_list(list) ->
              {subs, sub_errors} =
                Enum.reduce(list, {[], []}, fn sr, {found_acc, err_acc} ->
                  sub_path = Path.join([package_path, "usage-rules", "#{sr}.md"])

                  if Igniter.exists?(igniter, sub_path) do
                    {found_acc ++ [{package_name, package_path, sr, opts}], err_acc}
                  else
                    {found_acc,
                     err_acc ++
                       [
                         "Package :#{package_name} does not have a usage-rules/#{sr}.md file"
                       ]}
                  end
                end)

              {rules_acc ++ main ++ subs, errors_acc ++ sub_errors}
          end

        nil ->
          {rules_acc,
           errors_acc ++
             [
               "Package :#{package_name} is listed in usage_rules but is not a dependency of this project"
             ]}
      end
    end

    @builtin_aliases %{
      elixir: {:usage_rules, [sub_rules: ["elixir"]]},
      otp: {:usage_rules, [sub_rules: ["otp"]]}
    }

    defp parse_spec({inner, opts}) when is_list(opts) do
      {name, inner_opts} = parse_spec_inner(inner)
      {name, Keyword.merge(inner_opts, opts)}
    end

    defp parse_spec(spec) do
      parse_spec_inner(spec)
    end

    defp parse_spec_inner(spec) do
      case spec do
        atom when is_atom(atom) and is_map_key(@builtin_aliases, atom) ->
          @builtin_aliases[atom]

        atom when is_atom(atom) ->
          {atom, []}

        binary when is_binary(binary) ->
          case String.split(binary, ":", parts: 2) do
            [pkg] -> {String.to_atom(pkg), []}
            [pkg, "all"] -> {String.to_atom(pkg), [sub_rules: :all]}
            [pkg, sub] -> {String.to_atom(pkg), [sub_rules: [sub]]}
          end
      end
    end

    # -------------------------------------------------------------------
    # Sub-rule discovery
    # -------------------------------------------------------------------

    defp find_available_sub_rules(igniter, package_path) do
      usage_rules_dir = Path.join(package_path, "usage-rules")

      source_sub_rules =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, usage_rules_dir <> "/") &&
            String.ends_with?(path, ".md") &&
            !String.contains?(path, "/skills/")
        end)
        |> Enum.map(fn {path, _source} ->
          path |> Path.basename() |> Path.rootname()
        end)
        |> Enum.sort()

      if Enum.any?(source_sub_rules) do
        source_sub_rules
      else
        case File.ls(usage_rules_dir) do
          {:ok, entries} ->
            entries
            |> Enum.filter(&String.ends_with?(&1, ".md"))
            |> Enum.map(&Path.rootname/1)
            |> Enum.sort()

          {:error, _} ->
            []
        end
      end
    end

    # -------------------------------------------------------------------
    # AGENTS.md generation
    # -------------------------------------------------------------------

    defp cleanup_stale_usage_rules_section(igniter, file) do
      Igniter.update_file(igniter, file, fn source ->
        content = Rewrite.Source.get(source, :content)

        cond do
          String.contains?(content, "<!-- usage-rules-start -->") &&
              String.contains?(content, "<!-- usage-rules-end -->") ->
            [prelude, rest] = String.split(content, "<!-- usage-rules-start -->\n", parts: 2)
            [_old, postlude] = String.split(rest, "\n<!-- usage-rules-end -->", parts: 2)
            Rewrite.Source.update(source, :content, String.trim_trailing(prelude <> postlude))

          String.contains?(content, "<!-- usage-rules-start -->") ->
            [prelude, _old] = String.split(content, "<!-- usage-rules-start -->\n", parts: 2)
            Rewrite.Source.update(source, :content, String.trim_trailing(prelude))

          true ->
            source
        end
      end)
    end

    defp generate_usage_rules(igniter, file, package_rules) do
      package_contents = build_package_contents(igniter, package_rules)
      all_rules_content = Enum.map_join(package_contents, "\n", &elem(&1, 1))

      full_contents =
        "<!-- usage-rules-start -->\n" <>
          all_rules_content <>
          "\n<!-- usage-rules-end -->"

      Igniter.create_or_update_file(
        igniter,
        file,
        full_contents,
        fn source ->
          current = Rewrite.Source.get(source, :content)
          new_content = replace_usage_rules_section(current, package_contents)
          Rewrite.Source.update(source, :content, new_content)
        end
      )
    end

    defp build_package_contents(igniter, package_rules) do
      Enum.map(package_rules, fn {name, path, sub_rule, opts} ->
        section_name = section_name_for(name, sub_rule)
        description = package_description(name, sub_rule)
        description_part = if description == "", do: "", else: "_#{description}_\n\n"

        content =
          case opts[:link] do
            nil ->
              {usage_rules_path, _} = usage_rules_paths(name, path, sub_rule)
              read_dep_content(igniter, usage_rules_path)

            link_style ->
              build_link(name, sub_rule, section_name, link_style)
          end

        {section_name,
         "<!-- #{section_name}-start -->\n" <>
           "## #{section_name} usage\n" <>
           description_part <>
           content <>
           "\n<!-- #{section_name}-end -->"}
      end)
    end

    defp replace_usage_rules_section(current_contents, package_contents) do
      all_rules = Enum.map_join(package_contents, "\n", &elem(&1, 1))

      cond do
        # Both start and end markers present
        String.contains?(current_contents, "<!-- usage-rules-start -->") &&
            String.contains?(current_contents, "<!-- usage-rules-end -->") ->
          [prelude, rest] =
            String.split(current_contents, "<!-- usage-rules-start -->\n", parts: 2)

          [_old, postlude] = String.split(rest, "\n<!-- usage-rules-end -->", parts: 2)

          prelude <>
            "<!-- usage-rules-start -->\n" <>
            all_rules <>
            "\n<!-- usage-rules-end -->" <>
            postlude

        # Only start marker — treat everything after it as the old section
        String.contains?(current_contents, "<!-- usage-rules-start -->") ->
          [prelude, _old] =
            String.split(current_contents, "<!-- usage-rules-start -->\n", parts: 2)

          prelude <>
            "<!-- usage-rules-start -->\n" <>
            all_rules <>
            "\n<!-- usage-rules-end -->"

        # No markers at all — append
        true ->
          current_contents <>
            "\n<!-- usage-rules-start -->\n" <>
            all_rules <>
            "\n<!-- usage-rules-end -->\n"
      end
    end

    # -------------------------------------------------------------------
    # Stale skill cleanup
    # -------------------------------------------------------------------

    defp remove_stale_managed_skills(igniter, skills_location, current_build_names) do
      managed_skill_names = find_managed_skill_names(igniter, skills_location)
      stale = managed_skill_names -- current_build_names

      Enum.reduce(stale, igniter, fn skill_name, acc ->
        skill_dir = Path.join(skills_location, skill_name)
        skill_path = Path.join(skill_dir, "SKILL.md")

        custom_content =
          case Rewrite.source(acc.rewrite, skill_path) do
            {:ok, source} ->
              Rewrite.Source.get(source, :content)
              |> extract_skill_custom_content()

            {:error, _} ->
              ""
          end

        if custom_content != "" do
          # Preserve custom content, remove managed section and references
          acc =
            Igniter.update_file(acc, skill_path, fn source ->
              content = Rewrite.Source.get(source, :content)
              stripped = strip_managed_skill_content(content)
              Rewrite.Source.update(source, :content, stripped)
            end)

          # Remove reference files but keep SKILL.md
          acc.rewrite.sources
          |> Enum.filter(fn {path, _source} ->
            String.starts_with?(path, skill_dir <> "/") && path != skill_path
          end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.reduce(acc, fn path, inner_acc -> Igniter.rm(inner_acc, path) end)
        else
          # No custom content, remove everything
          paths_to_remove =
            acc.rewrite.sources
            |> Enum.filter(fn {path, _source} ->
              String.starts_with?(path, skill_dir <> "/")
            end)
            |> Enum.map(&elem(&1, 0))

          Enum.reduce(paths_to_remove, acc, fn path, inner_acc ->
            Igniter.rm(inner_acc, path)
          end)
        end
      end)
    end

    defp find_managed_skill_names(igniter, skills_location) do
      igniter.rewrite.sources
      |> Enum.filter(fn {path, source} ->
        content = Rewrite.Source.get(source, :content)

        String.starts_with?(path, skills_location <> "/") &&
          String.ends_with?(path, "/SKILL.md") &&
          String.contains?(content, "managed-by: usage-rules")
      end)
      |> Enum.map(fn {path, _source} ->
        path
        |> String.trim_leading(skills_location <> "/")
        |> String.split("/")
        |> hd()
      end)
      |> Enum.uniq()
    end

    # -------------------------------------------------------------------
    # Skill building (skills.build)
    # -------------------------------------------------------------------

    defp build_custom_skills(igniter, all_deps, build_specs, skills_location) do
      Enum.reduce(build_specs, igniter, fn {skill_name, skill_opts}, acc ->
        if Keyword.keyword?(skill_opts) do
          build_single_skill(acc, all_deps, skill_name, skill_opts, skills_location)
        else
          Igniter.add_issue(acc, """
          Invalid skill config for #{skill_name}. Expected a keyword list, got: #{inspect(skill_opts)}

          Example:

              build: [
                "#{skill_name}": [usage_rules: [:package1, :package2]]
              ]
          """)
        end
      end)
    end

    defp build_single_skill(igniter, all_deps, skill_name, skill_opts, skills_location) do
      skill_name = to_string(skill_name)
      skill_dir = Path.join(skills_location, skill_name)
      usage_rule_specs = skill_opts[:usage_rules] || []
      custom_description = skill_opts[:description]

      # Resolve which packages to include in this skill (supports atoms and regexes)
      resolved_packages = expand_dep_specs(usage_rule_specs, all_deps)

      if Enum.any?(resolved_packages) do
        generate_built_skill(
          igniter,
          skill_name,
          skill_dir,
          resolved_packages,
          custom_description
        )
      else
        igniter
      end
    end

    defp generate_built_skill(
           igniter,
           skill_name,
           skill_dir,
           resolved_packages,
           custom_description
         ) do
      skill_md =
        build_skill_md(igniter, skill_name, resolved_packages, custom_description)

      igniter =
        Igniter.create_or_update_file(
          igniter,
          Path.join(skill_dir, "SKILL.md"),
          skill_md,
          fn source ->
            current = Rewrite.Source.get(source, :content)
            new_content = update_skill_content(current, skill_md)
            Rewrite.Source.update(source, :content, new_content)
          end
        )

      # Reference files for sub-rules and main rules from all packages
      Enum.reduce(resolved_packages, igniter, fn {pkg_name, package_path, _mode}, acc ->
        # Create reference file for main usage-rules.md
        acc =
          case read_dep_content(acc, Path.join(package_path, "usage-rules.md")) do
            "" ->
              acc

            content ->
              ref_path = Path.join([skill_dir, "references", "#{pkg_name}.md"])

              Igniter.create_or_update_file(
                acc,
                ref_path,
                content,
                fn source -> Rewrite.Source.update(source, :content, content) end
              )
          end

        sub_rules = find_available_sub_rules(acc, package_path)

        Enum.reduce(sub_rules, acc, fn sub_rule, inner_acc ->
          sub_path = Path.join([package_path, "usage-rules", "#{sub_rule}.md"])
          content = read_dep_content(inner_acc, sub_path)
          ref_path = Path.join([skill_dir, "references", "#{sub_rule}.md"])

          Igniter.create_or_update_file(
            inner_acc,
            ref_path,
            content,
            fn source -> Rewrite.Source.update(source, :content, content) end
          )
        end)
      end)
    end

    defp build_skill_md(igniter, skill_name, resolved_packages, custom_description) do
      description = custom_description || build_skill_description(skill_name, resolved_packages)

      formatted_description = format_yaml_string(description)

      frontmatter =
        """
        ---
        name: #{skill_name}
        description: #{formatted_description}
        metadata:
          managed-by: #{@managed_by_marker}
        ---
        """
        |> String.trim_trailing()

      body = build_skill_body(igniter, skill_name, resolved_packages)

      frontmatter <>
        "\n\n" <>
        "<!-- usage-rules-skill-start -->\n" <>
        body <>
        "\n<!-- usage-rules-skill-end -->"
    end

    defp build_skill_description(skill_name, resolved_packages) do
      package_names = Enum.map(resolved_packages, &elem(&1, 0))

      descriptions =
        package_names
        |> Enum.map(&get_package_description/1)
        |> Enum.reject(&(&1 == ""))

      if Enum.any?(descriptions) do
        Enum.join(descriptions, ". ") <> "."
      else
        pkg_list = Enum.map_join(package_names, ", ", &to_string/1)
        "Usage rules, mix tasks, and documentation for #{skill_name} (#{pkg_list})."
      end
    end

    defp build_skill_body(igniter, _skill_name, resolved_packages) do
      sections = []

      # Sub-rules as references
      all_sub_rules =
        Enum.flat_map(resolved_packages, fn {_pkg_name, package_path, _mode} ->
          find_available_sub_rules(igniter, package_path)
        end)

      # All packages are references
      all_main_rules =
        Enum.map(resolved_packages, fn {pkg_name, _path, _mode} -> pkg_name end)

      all_references =
        Enum.map(all_sub_rules, fn sub_rule ->
          "- [#{sub_rule}](references/#{sub_rule}.md)"
        end) ++
          Enum.map(all_main_rules, fn pkg_name ->
            "- [#{pkg_name}](references/#{pkg_name}.md)"
          end)

      all_references = Enum.uniq(all_references)

      sections =
        if Enum.any?(all_references) do
          ref_lines = Enum.join(all_references, "\n")
          sections ++ ["## Additional References\n\n#{ref_lines}"]
        else
          sections
        end

      # Search docs for all packages
      package_names = Enum.map(resolved_packages, &elem(&1, 0))

      search_flags = Enum.map_join(package_names, " ", &"-p #{&1}")

      sections =
        sections ++
          [
            """
            ## Searching Documentation

            ```sh
            mix usage_rules.search_docs "search term" #{search_flags}
            ```
            """
            |> String.trim_trailing()
          ]

      # Mix tasks from all packages (at the bottom)
      all_mix_tasks =
        Enum.flat_map(resolved_packages, fn {pkg_name, _path, _mode} ->
          discover_mix_tasks(pkg_name)
          |> Enum.map(fn {task, doc} -> {pkg_name, task, doc} end)
        end)

      sections =
        if Enum.any?(all_mix_tasks) do
          task_lines =
            Enum.map_join(all_mix_tasks, "\n", fn {_pkg, task_name, shortdoc} ->
              desc = if shortdoc, do: " - #{shortdoc}", else: ""
              "- `mix #{task_name}`#{desc}"
            end)

          sections ++ ["## Available Mix Tasks\n\n#{task_lines}"]
        else
          sections
        end

      Enum.join(sections, "\n\n")
    end

    # -------------------------------------------------------------------
    # Package-provided skills
    # -------------------------------------------------------------------

    defp discover_package_skill_names(igniter, all_deps, package_skills_specs) do
      matching_packages = expand_package_skill_specs(package_skills_specs, all_deps)

      Enum.flat_map(matching_packages, fn {_pkg_name, pkg_path} ->
        find_package_skill_dirs(igniter, pkg_path)
      end)
      |> Enum.uniq()
    end

    defp sync_package_skills(igniter, all_deps, package_skills_specs, skills_location) do
      matching_packages = expand_package_skill_specs(package_skills_specs, all_deps)

      Enum.reduce(matching_packages, igniter, fn {pkg_name, pkg_path}, acc ->
        skill_dirs = find_package_skill_dirs(acc, pkg_path)

        Enum.reduce(skill_dirs, acc, fn skill_name, inner_acc ->
          src_skill_dir = Path.join([pkg_path, "usage-rules", "skills", skill_name])
          dst_skill_dir = Path.join(skills_location, skill_name)

          src_skill_path = Path.join(src_skill_dir, "SKILL.md")
          dst_skill_path = Path.join(dst_skill_dir, "SKILL.md")

          src_content = read_dep_content(inner_acc, src_skill_path)
          managed_content = package_skill_to_managed(src_content, pkg_name)

          inner_acc =
            Igniter.create_or_update_file(
              inner_acc,
              dst_skill_path,
              managed_content,
              fn source ->
                current = Rewrite.Source.get(source, :content)
                new_content = update_skill_content(current, managed_content)
                Rewrite.Source.update(source, :content, new_content)
              end
            )

          # Copy any companion files (e.g. references/) verbatim
          companion_files = find_package_skill_companions(inner_acc, src_skill_dir)

          Enum.reduce(companion_files, inner_acc, fn {rel_path, content}, acc2 ->
            dst_path = Path.join(dst_skill_dir, rel_path)

            Igniter.create_or_update_file(
              acc2,
              dst_path,
              content,
              fn source -> Rewrite.Source.update(source, :content, content) end
            )
          end)
        end)
      end)
    end

    defp expand_package_skill_specs(specs, all_deps) do
      Enum.flat_map(specs, fn
        %Regex{} = regex ->
          Enum.filter(all_deps, fn {name, _path} -> Regex.match?(regex, to_string(name)) end)

        pkg_name when is_atom(pkg_name) ->
          case Enum.find(all_deps, fn {name, _path} -> name == pkg_name end) do
            nil -> []
            dep -> [dep]
          end
      end)
      |> Enum.uniq_by(&elem(&1, 0))
    end

    defp find_package_skill_dirs(igniter, package_path) do
      skills_dir = Path.join([package_path, "usage-rules", "skills"])

      source_skill_dirs =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, skills_dir <> "/") &&
            String.ends_with?(path, "/SKILL.md")
        end)
        |> Enum.map(fn {path, _} ->
          path
          |> String.trim_leading(skills_dir <> "/")
          |> String.split("/")
          |> hd()
        end)
        |> Enum.sort()

      if Enum.any?(source_skill_dirs) do
        source_skill_dirs
      else
        case File.ls(skills_dir) do
          {:ok, entries} ->
            entries
            |> Enum.filter(fn entry ->
              File.exists?(Path.join([skills_dir, entry, "SKILL.md"]))
            end)
            |> Enum.sort()

          {:error, _} ->
            []
        end
      end
    end

    defp find_package_skill_companions(igniter, src_skill_dir) do
      source_companions =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, src_skill_dir <> "/") &&
            !String.ends_with?(path, "/SKILL.md")
        end)
        |> Enum.map(fn {path, source} ->
          rel = String.trim_leading(path, src_skill_dir <> "/")
          content = Rewrite.Source.get(source, :content)
          {rel, content}
        end)

      if Enum.any?(source_companions) do
        source_companions
      else
        case File.ls(src_skill_dir) do
          {:ok, entries} ->
            entries
            |> Enum.flat_map(fn entry ->
              full = Path.join(src_skill_dir, entry)

              cond do
                entry == "SKILL.md" ->
                  []

                File.dir?(full) ->
                  case File.ls(full) do
                    {:ok, sub_entries} ->
                      Enum.flat_map(sub_entries, fn sub ->
                        sub_full = Path.join(full, sub)

                        if File.regular?(sub_full) do
                          [{Path.join(entry, sub), File.read!(sub_full)}]
                        else
                          []
                        end
                      end)

                    {:error, _} ->
                      []
                  end

                File.regular?(full) ->
                  [{entry, File.read!(full)}]

                true ->
                  []
              end
            end)

          {:error, _} ->
            []
        end
      end
    end

    defp package_skill_to_managed(content, _pkg_name) do
      content = strip_spdx_comments(content)

      case Regex.run(~r/\A(---\n.*?\n---\n*)(.*)\z/s, content) do
        [_, frontmatter, body] ->
          managed_frontmatter = inject_managed_metadata(frontmatter)

          managed_frontmatter <>
            "\n<!-- usage-rules-skill-start -->\n" <>
            String.trim(body) <>
            "\n<!-- usage-rules-skill-end -->"

        nil ->
          "---\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\n" <>
            String.trim(content) <>
            "\n<!-- usage-rules-skill-end -->"
      end
    end

    defp inject_managed_metadata(frontmatter) do
      cond do
        String.contains?(frontmatter, "managed-by:") ->
          frontmatter

        String.contains?(frontmatter, "metadata:") ->
          String.replace(
            frontmatter,
            "metadata:",
            "metadata:\n  managed-by: usage-rules",
            global: false
          )

        true ->
          String.replace(
            frontmatter,
            "\n---",
            "\nmetadata:\n  managed-by: usage-rules\n---",
            global: false
          )
      end
    end

    # -------------------------------------------------------------------
    # Mix task discovery
    # -------------------------------------------------------------------

    defp discover_mix_tasks(package_name) do
      Application.load(package_name)

      case Application.spec(package_name, :modules) do
        nil ->
          []

        modules ->
          modules
          |> Enum.filter(fn mod ->
            Atom.to_string(mod) |> String.starts_with?("Elixir.Mix.Tasks.")
          end)
          |> Enum.map(fn mod ->
            Code.ensure_loaded(mod)
            {Mix.Task.task_name(mod), module_shortdoc(mod)}
          end)
          |> Enum.sort_by(&elem(&1, 0))
      end
    end

    defp module_shortdoc(mod) do
      if Code.ensure_loaded?(mod) && function_exported?(mod, :__info__, 1) do
        case Keyword.get(mod.__info__(:attributes), :shortdoc) do
          [doc] when is_binary(doc) -> doc
          _ -> nil
        end
      else
        nil
      end
    end

    # -------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------

    defp expand_dep_specs(specs, all_deps) do
      Enum.flat_map(specs, fn
        {%Regex{} = regex, :reference} ->
          IO.warn(
            "{~r/.../, :reference} is deprecated in usage_rules skill config. " <>
              "All packages are now automatically written as reference files. " <>
              "Use the regex directly instead: ~r/#{Regex.source(regex)}/"
          )

          Enum.filter(all_deps, fn {name, _path} ->
            Regex.match?(regex, to_string(name))
          end)
          |> Enum.map(fn {name, path} -> {name, path, :reference} end)

        {pkg_name, :reference} when is_atom(pkg_name) ->
          IO.warn(
            "{:#{pkg_name}, :reference} is deprecated in usage_rules skill config. " <>
              "All packages are now automatically written as reference files. " <>
              "Use the atom directly instead: :#{pkg_name}"
          )

          case Enum.find(all_deps, fn {name, _path} -> name == pkg_name end) do
            nil -> []
            {name, path} -> [{name, path, :reference}]
          end

        %Regex{} = regex ->
          Enum.filter(all_deps, fn {name, _path} ->
            Regex.match?(regex, to_string(name))
          end)
          |> Enum.map(fn {name, path} -> {name, path, :reference} end)

        pkg_name when is_atom(pkg_name) ->
          case Enum.find(all_deps, fn {name, _path} -> name == pkg_name end) do
            nil -> []
            {name, path} -> [{name, path, :reference}]
          end
      end)
      |> Enum.uniq_by(&elem(&1, 0))
    end

    defp section_name_for(name, nil), do: to_string(name)
    defp section_name_for(name, sub_rule), do: "#{name}:#{sub_rule}"

    defp usage_rules_paths(name, path, nil) do
      {Path.join(path, "usage-rules.md"), "#{name}.md"}
    end

    defp usage_rules_paths(name, path, sub_rule) do
      {Path.join([path, "usage-rules", "#{sub_rule}.md"]), "#{name}_#{sub_rule}.md"}
    end

    defp read_dep_content(igniter, path) do
      content =
        case Rewrite.source(igniter.rewrite, path) do
          {:ok, source} ->
            Rewrite.Source.get(source, :content)

          {:error, _} ->
            if File.exists?(path) do
              File.read!(path)
            else
              ""
            end
        end

      strip_spdx_comments(content)
    end

    defp package_description(name, nil) do
      get_package_description(name)
    end

    defp package_description(_name, _sub_rule), do: ""

    defp get_package_description(name) do
      case Application.spec(name, :description) do
        nil -> ""
        desc -> String.trim_trailing(to_string(desc))
      end
    end

    defp build_link(name, nil, _section_name, :at) do
      "@deps/#{name}/usage-rules.md"
    end

    defp build_link(name, nil, _section_name, _link_style) do
      "[#{name} usage rules](deps/#{name}/usage-rules.md)"
    end

    defp build_link(name, sub_rule, _section_name, :at) do
      "@deps/#{name}/usage-rules/#{sub_rule}.md"
    end

    defp build_link(name, sub_rule, section_name, _link_style) do
      "[#{section_name} usage rules](deps/#{name}/usage-rules/#{sub_rule}.md)"
    end

    defp extract_skill_custom_content(content) do
      if String.contains?(content, "<!-- usage-rules-skill-start -->") do
        [prelude, _] = String.split(content, "<!-- usage-rules-skill-start -->", parts: 2)

        case Regex.run(~r/\A---\n.*?\n---\n*(.*)/s, prelude) do
          [_, custom] -> String.trim(custom)
          _ -> ""
        end
      else
        ""
      end
    end

    defp update_skill_content(current_content, new_skill_md) do
      if String.contains?(current_content, "<!-- usage-rules-skill-start -->") do
        custom = extract_skill_custom_content(current_content)

        if custom != "" do
          [new_frontmatter, new_managed] =
            String.split(new_skill_md, "\n\n<!-- usage-rules-skill-start -->", parts: 2)

          new_frontmatter <>
            "\n\n" <> custom <> "\n\n<!-- usage-rules-skill-start -->" <> new_managed
        else
          new_skill_md
        end
      else
        new_skill_md
      end
    end

    defp strip_managed_skill_content(content) do
      # Remove managed-by metadata from frontmatter
      content = String.replace(content, ~r/metadata:\n\s+managed-by: usage-rules\n/, "")

      # Remove managed section
      if String.contains?(content, "<!-- usage-rules-skill-start -->") do
        [prelude, rest] =
          String.split(content, "\n\n<!-- usage-rules-skill-start -->\n", parts: 2)

        postlude =
          case String.split(rest, "\n<!-- usage-rules-skill-end -->", parts: 2) do
            [_, post] -> post
            _ -> ""
          end

        String.trim_trailing(prelude <> postlude)
      else
        content
      end
    end

    defp strip_spdx_comments(content) do
      String.replace(content, ~r/\A\s*<!--\s*\n(?:.*?SPDX-.*?\n)*.*?-->\s*\n*/s, "")
    end

    defp format_yaml_string(str) do
      str = String.trim(str)

      if String.contains?(str, "\n") do
        indent = "  "

        lines =
          str
          |> String.split("\n")
          |> Enum.map_join("\n", fn line ->
            trimmed = String.trim(line)
            if trimmed == "", do: "", else: indent <> trimmed
          end)

        ">-\n" <> lines
      else
        "\"" <> escape_yaml(str) <> "\""
      end
    end

    defp escape_yaml(str) do
      str
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
    end
  end
else
  defmodule Mix.Tasks.UsageRules.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.raise("""
      The task 'usage_rules.sync' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)
    end
  end
end
