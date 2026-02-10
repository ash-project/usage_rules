# SPDX-FileCopyrightText: 2025 agents_md contributors <https://github.com/ash-project/agents_md/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AgentsMd.Sync.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Sync AGENTS.md and agent skills from project config"
  end

  @spec example() :: String.t()
  def example do
    "mix agents_md.sync"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    Reads the `:agents_md` key from your project config in `mix.exs` and generates
    an AGENTS.md file with usage rules from your dependencies, optionally generating
    agent skills as well.

    ## Configuration

    Add to your `mix.exs` project config:

    ```elixir
    def project do
      [
        agents_md: agents_md()
      ]
    end

    defp agents_md do
      [
        file: "AGENTS.md",
        usage_rules: [
          :ash,                          # main usage-rules.md
          "phoenix:ecto",                # specific sub-rule
          :req,
        ],
        # or: usage_rules: :all
        skills: [
          location: ".claude/skills",    # where to output skills
          packages: [:ash],              # symlink pre-made skills from deps
          build: [                       # compose custom skills from usage rules
            "ash-expert": [
              description: "Expert on the Ash Framework ecosystem.",
              usage_rules: [:ash, :ash_postgres, :ash_json_api]
            ],
            "use-req": [usage_rules: [:req]]
          ]
        ],
        link_to_folder: "deps",
        link_style: "markdown",          # "markdown" or "at"
        inline: ["agents_md:all"]        # force-inline specific specs
      ]
    end
    ```

    Then run:
    ```sh
    #{example()}
    ```

    The config is the source of truth — packages present in the file but absent
    from config are automatically removed on each sync.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AgentsMd.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @managed_by_marker "agents-md"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :agents_md,
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

      n
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
        igniter.assigns[:agents_md_config] || []
      else
        Mix.Project.config()[:agents_md] || []
      end
    end

    defp validate_config(config) do
      cond do
        !Keyword.keyword?(config) ->
          {:error, "agents_md config must be a keyword list"}

        is_nil(config[:file]) && is_nil(config[:usage_rules]) && is_nil(config[:skills]) ->
          {:error,
           """
           No agents_md config found. Add to your mix.exs project config:

               def project do
                 [
                   agents_md: agents_md()
                 ]
               end

               defp agents_md do
                 [
                   file: "AGENTS.md",
                   usage_rules: [:ash, :phoenix],
                   link_to_folder: "deps"
                 ]
               end
           """}

        config[:link_style] && config[:link_style] not in ["markdown", "at"] ->
          {:error, "agents_md link_style must be \"markdown\" or \"at\""}

        true ->
          :ok
      end
    end

    defp include_dep_sources(igniter) do
      igniter
      |> Igniter.include_glob("deps/*/usage-rules.md")
      |> Igniter.include_glob("deps/*/usage-rules/*.md")
      |> Igniter.include_glob("deps/*/skills/*/SKILL.md")
      |> Igniter.include_glob("deps/*/skills/*/**/*")
    end

    # -------------------------------------------------------------------
    # Main sync orchestration
    # -------------------------------------------------------------------

    defp sync(igniter, config) do
      all_deps = discover_deps(igniter)

      file = config[:file]
      usage_rules_config = config[:usage_rules]
      skills_config = config[:skills] || []
      link_to_folder = config[:link_to_folder]
      link_style = config[:link_style] || "markdown"
      inline_specs = parse_inline_specs(config[:inline])

      # Resolve usage rules packages
      {package_rules, errors} = resolve_usage_rules(igniter, all_deps, usage_rules_config)

      # Report any resolution errors as issues
      igniter =
        Enum.reduce(errors, igniter, fn error, acc ->
          Igniter.add_issue(acc, error)
        end)

      # Generate AGENTS.md if file is configured and there are packages to sync
      igniter =
        if file && !Enum.any?(errors) && Enum.any?(package_rules) do
          igniter
          |> generate_agents_md(file, package_rules, link_to_folder, link_style, inline_specs)
        else
          igniter
        end

      skills_location = skills_config[:location] || ".claude/skills"

      # Build custom skills from usage rules and remove stale managed skills
      build_specs = skills_config[:build] || []
      build_names = Enum.map(build_specs, fn {name, _opts} -> to_string(name) end)

      igniter = remove_stale_managed_skills(igniter, skills_location, build_names)

      igniter =
        if Enum.any?(build_specs) do
          build_custom_skills(igniter, all_deps, build_specs, skills_location)
        else
          igniter
        end

      # Symlink pre-made skills from skills.packages
      skills_packages = skills_config[:packages] || []

      igniter =
        if Enum.any?(skills_packages) do
          symlink_premade_skills(igniter, all_deps, skills_packages, skills_location)
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
      (mix_deps ++ igniter_deps) |> Enum.uniq()
    end

    defp get_deps_from_igniter(igniter) do
      if igniter.assigns[:test_mode?] do
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.match?(path, ~r|^deps/[^/]+/usage-rules\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/usage-rules/[^/]+\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/skills/[^/]+/SKILL\.md$|)
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

    defp resolve_usage_rules(igniter, all_deps, :all) do
      rules =
        get_packages_with_usage_rules(igniter, all_deps)
        |> Enum.flat_map(fn {package_name, package_path} ->
          main_rules =
            if Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
              [{package_name, package_path, nil, []}]
            else
              []
            end

          sub_rules =
            find_available_sub_rules(igniter, package_path)
            |> Enum.map(fn sub_rule_name ->
              {package_name, package_path, sub_rule_name, []}
            end)

          main_rules ++ sub_rules
        end)

      {rules, []}
    end

    defp resolve_usage_rules(igniter, all_deps, specs) when is_list(specs) do
      {rules, errors} =
        Enum.reduce(specs, {[], []}, fn spec, {rules_acc, errors_acc} ->
          {package_name, sub_rule} = parse_spec(spec)

          case Enum.find(all_deps, fn {name, _path} -> name == package_name end) do
            {_name, package_path} ->
              case sub_rule do
                "all" ->
                  found =
                    find_available_sub_rules(igniter, package_path)
                    |> Enum.map(fn sr -> {package_name, package_path, sr, []} end)

                  if Enum.any?(found) do
                    {rules_acc ++ found, errors_acc}
                  else
                    {rules_acc,
                     errors_acc ++
                       [
                         "Package :#{package_name} is a dependency but has no sub-rules in usage-rules/"
                       ]}
                  end

                nil ->
                  if Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
                    {rules_acc ++ [{package_name, package_path, nil, []}], errors_acc}
                  else
                    {rules_acc,
                     errors_acc ++
                       [
                         "Package :#{package_name} is a dependency but does not have a usage-rules.md file"
                       ]}
                  end

                sub_rule_name ->
                  sub_path = Path.join([package_path, "usage-rules", "#{sub_rule_name}.md"])

                  if Igniter.exists?(igniter, sub_path) do
                    {rules_acc ++ [{package_name, package_path, sub_rule_name, []}], errors_acc}
                  else
                    {rules_acc,
                     errors_acc ++
                       [
                         "Package :#{package_name} does not have a usage-rules/#{sub_rule_name}.md file"
                       ]}
                  end
              end

            nil ->
              {rules_acc,
               errors_acc ++
                 [
                   "Package :#{package_name} is listed in usage_rules but is not a dependency of this project"
                 ]}
          end
        end)

      {rules, errors}
    end

    @builtin_aliases %{
      elixir: {:agents_md, "elixir"},
      otp: {:agents_md, "otp"}
    }

    defp parse_spec(spec) do
      case spec do
        atom when is_atom(atom) and is_map_key(@builtin_aliases, atom) ->
          @builtin_aliases[atom]

        atom when is_atom(atom) ->
          {atom, nil}

        binary when is_binary(binary) ->
          case String.split(binary, ":", parts: 2) do
            [pkg] -> {String.to_atom(pkg), nil}
            [pkg, sub] -> {String.to_atom(pkg), sub}
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

    defp generate_agents_md(
           igniter,
           file,
           package_rules,
           link_to_folder,
           link_style,
           inline_specs
         ) do
      if link_to_folder do
        generate_with_folder_links(
          igniter,
          file,
          package_rules,
          link_to_folder,
          link_style,
          inline_specs
        )
      else
        generate_inline(igniter, file, package_rules)
      end
    end

    defp generate_inline(igniter, file, package_rules) do
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

    defp generate_with_folder_links(
           igniter,
           file,
           package_rules,
           folder_name,
           link_style,
           inline_specs
         ) do
      # Create individual files in the folder (unless folder is "deps")
      igniter =
        if folder_name == "deps" do
          igniter
        else
          Enum.reduce(package_rules, igniter, fn {name, path, sub_rule, _opts}, acc ->
            if should_inline?(name, sub_rule, inline_specs) do
              acc
            else
              {usage_rules_path, target_file_name} = usage_rules_paths(name, path, sub_rule)

              content = read_dep_content(acc, usage_rules_path)
              package_file_path = Path.join(folder_name, target_file_name)

              Igniter.create_or_update_file(
                acc,
                package_file_path,
                content,
                fn source -> Rewrite.Source.update(source, :content, content) end
              )
            end
          end)
        end

      # Build the main file with links or inline content
      package_contents =
        Enum.map(package_rules, fn {name, path, sub_rule, _opts} ->
          section_name = section_name_for(name, sub_rule)
          description = package_description(name, sub_rule)
          description_part = if description == "", do: "", else: "_#{description}_\n\n"

          content =
            if should_inline?(name, sub_rule, inline_specs) do
              {usage_rules_path, _} = usage_rules_paths(name, path, sub_rule)
              read_dep_content(igniter, usage_rules_path)
            else
              build_link(name, sub_rule, section_name, folder_name, link_style)
            end

          {section_name,
           "<!-- #{section_name}-start -->\n" <>
             "## #{section_name} usage\n" <>
             description_part <>
             content <>
             "\n<!-- #{section_name}-end -->"}
        end)

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
      Enum.map(package_rules, fn {name, path, sub_rule, _opts} ->
        section_name = section_name_for(name, sub_rule)
        {usage_rules_path, _} = usage_rules_paths(name, path, sub_rule)
        content = read_dep_content(igniter, usage_rules_path)
        description = package_description(name, sub_rule)
        description_part = if description == "", do: "", else: "_#{description}_\n\n"

        {section_name,
         "<!-- #{section_name}-start -->\n" <>
           "## #{section_name} usage\n" <>
           description_part <>
           content <>
           "\n<!-- #{section_name}-end -->"}
      end)
    end

    defp replace_usage_rules_section(current_contents, package_contents) do
      case String.split(current_contents, [
             "<!-- usage-rules-start -->\n",
             "\n<!-- usage-rules-end -->"
           ]) do
        [prelude, _current_packages, postlude] ->
          # Always replace entire section (config is source of truth)
          all_rules = Enum.map_join(package_contents, "\n", &elem(&1, 1))

          prelude <>
            "<!-- usage-rules-start -->\n" <>
            all_rules <>
            "\n<!-- usage-rules-end -->" <>
            postlude

        _ ->
          all_rules = Enum.map_join(package_contents, "\n", &elem(&1, 1))

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

        if acc.assigns[:test_mode?] do
          remove_skill_from_sources(acc, skill_dir)
        else
          if File.exists?(skill_dir) do
            File.rm_rf!(skill_dir)
          end

          acc
        end
      end)
    end

    defp find_managed_skill_names(igniter, skills_location) do
      source_names =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, skills_location <> "/") &&
            String.ends_with?(path, "/SKILL.md")
        end)
        |> Enum.filter(fn {_path, source} ->
          content = Rewrite.Source.get(source, :content)
          String.contains?(content, "managed-by: agents-md")
        end)
        |> Enum.map(fn {path, _source} ->
          path
          |> String.trim_leading(skills_location <> "/")
          |> String.split("/")
          |> hd()
        end)
        |> Enum.uniq()

      fs_names =
        if !igniter.assigns[:test_mode?] && File.dir?(skills_location) do
          case File.ls(skills_location) do
            {:ok, entries} ->
              Enum.filter(entries, fn entry ->
                skill_md = Path.join([skills_location, entry, "SKILL.md"])

                File.exists?(skill_md) &&
                  String.contains?(File.read!(skill_md), "managed-by: agents-md")
              end)

            {:error, _} ->
              []
          end
        else
          []
        end

      Enum.uniq(source_names ++ fs_names)
    end

    defp remove_skill_from_sources(igniter, skill_dir) do
      paths_to_remove =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, skill_dir <> "/")
        end)
        |> Enum.map(&elem(&1, 0))

      Enum.reduce(paths_to_remove, igniter, fn path, acc ->
        %{acc | rewrite: Rewrite.drop(acc.rewrite, [path])}
      end)
    end

    # -------------------------------------------------------------------
    # Skill building (skills.build)
    # -------------------------------------------------------------------

    defp build_custom_skills(igniter, all_deps, build_specs, skills_location) do
      Enum.reduce(build_specs, igniter, fn {skill_name, skill_opts}, acc ->
        unless Keyword.keyword?(skill_opts) do
          Igniter.add_issue(acc, """
          Invalid skill config for #{skill_name}. Expected a keyword list, got: #{inspect(skill_opts)}

          Example:

              build: [
                "#{skill_name}": [usage_rules: [:package1, :package2]]
              ]
          """)
        else
          build_single_skill(acc, all_deps, skill_name, skill_opts, skills_location)
        end
      end)
    end

    defp build_single_skill(igniter, all_deps, skill_name, skill_opts, skills_location) do
      skill_name = to_string(skill_name)
      skill_dir = Path.join(skills_location, skill_name)
      usage_rule_packages = skill_opts[:usage_rules] || []
      custom_description = skill_opts[:description]

      # Resolve which packages to include in this skill
      resolved_packages =
        Enum.flat_map(usage_rule_packages, fn pkg_name ->
          case Enum.find(all_deps, fn {name, _path} -> name == pkg_name end) do
            {name, path} -> [{name, path}]
            nil -> []
          end
        end)

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
      skill_md = build_skill_md(igniter, skill_name, resolved_packages, custom_description)

      igniter =
        Igniter.create_or_update_file(
          igniter,
          Path.join(skill_dir, "SKILL.md"),
          skill_md,
          fn source -> Rewrite.Source.update(source, :content, skill_md) end
        )

      # Reference files for sub-rules from all packages
      Enum.reduce(resolved_packages, igniter, fn {_pkg_name, package_path}, acc ->
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

      frontmatter =
        """
        ---
        name: #{skill_name}
        description: "#{escape_yaml(description)}"
        metadata:
          managed-by: #{@managed_by_marker}
        ---
        """
        |> String.trim_trailing()

      body = build_skill_body(igniter, skill_name, resolved_packages)

      frontmatter <> "\n\n" <> body
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

      # Usage rules content from all packages
      sections =
        Enum.reduce(resolved_packages, sections, fn {pkg_name, package_path}, acc ->
          main_path = Path.join(package_path, "usage-rules.md")
          content = read_dep_content(igniter, main_path)

          if content != "" do
            acc ++ ["## #{pkg_name} usage rules\n\n#{content}"]
          else
            acc
          end
        end)

      # Mix tasks from all packages
      all_mix_tasks =
        Enum.flat_map(resolved_packages, fn {pkg_name, _path} ->
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

      # Search docs for all packages
      package_names = Enum.map(resolved_packages, &elem(&1, 0))

      search_flags = Enum.map_join(package_names, " ", &"-p #{&1}")

      sections =
        sections ++
          [
            """
            ## Searching Documentation

            ```sh
            mix agents_md.search_docs "search term" #{search_flags}
            ```
            """
            |> String.trim_trailing()
          ]

      # Sub-rules as references
      all_sub_rules =
        Enum.flat_map(resolved_packages, fn {_pkg_name, package_path} ->
          find_available_sub_rules(igniter, package_path)
        end)

      sections =
        if Enum.any?(all_sub_rules) do
          ref_lines =
            Enum.map_join(all_sub_rules, "\n", fn sub_rule ->
              "- [#{sub_rule}](references/#{sub_rule}.md)"
            end)

          sections ++ ["## Additional References\n\n#{ref_lines}"]
        else
          sections
        end

      Enum.join(sections, "\n\n")
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
    # Pre-made skills (symlinked from deps/<pkg>/skills/)
    # -------------------------------------------------------------------

    defp symlink_premade_skills(igniter, all_deps, skill_package_names, skills_location) do
      Enum.reduce(skill_package_names, igniter, fn pkg_name, acc ->
        case Enum.find(all_deps, fn {name, _path} -> name == pkg_name end) do
          {_name, package_path} ->
            skills_dir = Path.join(package_path, "skills")

            find_premade_skill_names(acc, skills_dir)
            |> Enum.reduce(acc, fn skill_name, inner_acc ->
              source = Path.join(skills_dir, skill_name)
              target = Path.join(skills_location, skill_name)

              if inner_acc.assigns[:test_mode?] do
                copy_premade_skill_for_test(inner_acc, skill_name, source, skills_location)
              else
                create_symlink(inner_acc, source, target)
              end
            end)

          nil ->
            acc
        end
      end)
    end

    defp find_premade_skill_names(igniter, skills_dir) do
      source_names =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, skills_dir <> "/") &&
            String.ends_with?(path, "/SKILL.md")
        end)
        |> Enum.map(fn {path, _source} ->
          path
          |> String.trim_leading(skills_dir <> "/")
          |> String.split("/")
          |> hd()
        end)
        |> Enum.uniq()
        |> Enum.sort()

      if Enum.any?(source_names) do
        source_names
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

    defp create_symlink(igniter, source_path, target_path) do
      abs_source = Path.expand(source_path)
      File.mkdir_p!(Path.dirname(target_path))

      case File.read_link(target_path) do
        {:ok, existing} ->
          if Path.expand(existing) != abs_source do
            File.rm!(target_path)
            File.ln_s!(abs_source, target_path)
          end

        {:error, _} ->
          if File.exists?(target_path), do: File.rm_rf!(target_path)
          File.ln_s!(abs_source, target_path)
      end

      igniter
    end

    defp copy_premade_skill_for_test(igniter, skill_name, source_dir, skills_location) do
      source_files =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, source_dir <> "/")
        end)
        |> Enum.map(fn {path, _source} -> path end)

      Enum.reduce(source_files, igniter, fn source_path, acc ->
        relative = String.trim_leading(source_path, source_dir <> "/")
        target = Path.join([skills_location, skill_name, relative])

        content =
          case Rewrite.source(acc.rewrite, source_path) do
            {:ok, source} -> Rewrite.Source.get(source, :content)
            {:error, _} -> ""
          end

        Igniter.create_or_update_file(
          acc,
          target,
          content,
          fn source -> Rewrite.Source.update(source, :content, content) end
        )
      end)
    end

    # -------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------

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

    defp build_link(name, nil, _section_name, folder_name, link_style) do
      case {link_style, folder_name} do
        {"at", "deps"} -> "@deps/#{name}/usage-rules.md"
        {"at", _} -> "@#{folder_name}/#{name}.md"
        {_, "deps"} -> "[#{name} usage rules](deps/#{name}/usage-rules.md)"
        _ -> "[#{name} usage rules](#{folder_name}/#{name}.md)"
      end
    end

    defp build_link(name, sub_rule, section_name, folder_name, link_style) do
      case {link_style, folder_name} do
        {"at", "deps"} -> "@deps/#{name}/usage-rules/#{sub_rule}.md"
        {"at", _} -> "@#{folder_name}/#{name}_#{sub_rule}.md"
        {_, "deps"} -> "[#{section_name} usage rules](deps/#{name}/usage-rules/#{sub_rule}.md)"
        _ -> "[#{section_name} usage rules](#{folder_name}/#{name}_#{sub_rule}.md)"
      end
    end

    defp should_inline?(package_name, sub_rule, inline_specs) do
      pkg_str = to_string(package_name)

      section =
        case sub_rule do
          nil -> pkg_str
          sr -> "#{pkg_str}:#{sr}"
        end

      Enum.any?(inline_specs, fn spec ->
        case String.split(spec, ":", parts: 2) do
          [^pkg_str] when sub_rule == nil -> true
          [^pkg_str, "all"] -> true
          [^pkg_str, ^sub_rule] when sub_rule != nil -> true
          [^section] -> true
          ["agents_md", "all"] when sub_rule != nil -> true
          _ -> false
        end
      end)
    end

    defp parse_inline_specs(nil), do: []

    defp parse_inline_specs(specs) when is_list(specs), do: Enum.map(specs, &to_string/1)

    defp parse_inline_specs(specs) when is_binary(specs) do
      specs |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

    defp strip_spdx_comments(content) do
      String.replace(content, ~r/\A\s*<!--\s*\n(?:.*?SPDX-.*?\n)*.*?-->\s*\n*/s, "")
    end

    defp escape_yaml(str) do
      str
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
    end
  end
else
  defmodule Mix.Tasks.AgentsMd.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'agents_md.sync' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
