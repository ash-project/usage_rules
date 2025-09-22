defmodule Mix.Tasks.UsageRules.Sync.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Combine the package rules for the provided packages into the provided file, or list/gather all dependencies."
  end

  @spec example() :: String.t()
  def example do
    "mix usage_rules.sync CLAUDE.md --all --link-to-folder deps"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    ## Package Specifications

    Packages can be specified in the following formats:
    * `package_name` - Include the main usage-rules.md file for the package
    * `package_name:sub_rule` - Include a specific sub-rule from the package's usage-rules/ folder
    * `package_name:all` - Include all sub-rules from the package's usage-rules/ folder

    Sub-rules are discovered from `usage-rules/` folders within package directories. For example:
    * `deps/ash/usage-rules/testing.md` can be included with `ash:testing`
    * `deps/phoenix/usage-rules/views.md` can be included with `phoenix:views`

    ## Options

    * `--all` - Gather usage rules from all dependencies that have them (includes both main rules and all sub-rules)
    * `--list` - List all dependencies with usage rules. If a file is provided, shows status (present, missing, stale)
    * `--remove` - Remove specified packages from the target file instead of adding them
    * `--remove-missing` - Remove any packages from the target file that are not listed in the command
    * `--link-to-folder <folder>` - Save usage rules for each package in separate files within the specified folder and create links to them
    * `--link-style <style>` - Style of links to create when using --link-to-folder (markdown|at). Defaults to 'markdown'
    * `--inline <specs>` - Force specific packages to be inlined even when using --link-to-folder. Supports same specs as packages (comma-separated)
    * `--folder-only <folder>` - Extract usage rules to the specified folder without updating any other files
    * `--merge-sub-rules` - When used with --folder-only, merge sub-rules into the same file per package

    ## Examples

    Combine specific packages:
    ```sh
    #{example()}
    ```

    Gather all dependencies with usage rules:
    ```sh
    mix usage_rules.sync CLAUDE.md --all
    ```

    List all dependencies with usage rules:
    ```sh
    mix usage_rules.sync --list
    ```

    Check status of dependencies against a specific file:
    ```sh
    mix usage_rules.sync CLAUDE.md --list
    ```

    Remove specific packages from a file:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --remove
    ```

    Save usage rules to individual files in a folder with markdown links:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder rules
    ```

    Save usage rules with @-style links:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder rules --link-style at
    ```

    Link directly to deps files without copying:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --link-to-folder deps
    ```

    Combine all dependencies with folder links:
    ```sh
    mix usage_rules.sync CLAUDE.md --all --link-to-folder docs
    ```

    Check status of packages using folder links:
    ```sh
    mix usage_rules.sync CLAUDE.md --list --link-to-folder rules
    ```

    Remove packages and their folder files:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --remove --link-to-folder rules
    ```

    Include specific sub-rules:
    ```sh
    mix usage_rules.sync CLAUDE.md ash:testing phoenix:views
    ```

    Include all sub-rules from a package:
    ```sh
    mix usage_rules.sync CLAUDE.md ash:all
    ```

    Mix main package rules with sub-rules:
    ```sh
    mix usage_rules.sync CLAUDE.md ash ash:testing phoenix:views
    ```

    Inline all sub-rules while linking main packages (recommended for agents):
    ```sh
    mix usage_rules.sync AGENTS.md --all --inline usage_rules:all --link-to-folder deps
    ```

    Inline specific packages while linking others:
    ```sh
    mix usage_rules.sync CLAUDE.md ash:testing phoenix --inline ash:testing --link-to-folder docs
    ```

    Remove unused packages that are no longer dependencies:
    ```sh
    mix usage_rules.sync CLAUDE.md ash phoenix --remove-missing
    ```

    Extract usage rules to folder without updating any files:
    ```sh
    mix usage_rules.sync ash phoenix --folder-only rules
    ```

    Extract all usage rules to folder:
    ```sh
    mix usage_rules.sync --all --folder-only docs
    ```

    Extract sub-rules as separate files:
    ```sh
    mix usage_rules.sync ash:testing ash:queries --folder-only rules
    ```

    Extract and merge sub-rules into single files per package:
    ```sh
    mix usage_rules.sync ash:testing ash:queries --folder-only rules --merge-sub-rules
    ```

    Extract all usage rules with merging:
    ```sh
    mix usage_rules.sync --all --folder-only docs --merge-sub-rules
    ```

    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.UsageRules.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :usage_rules,
        example: __MODULE__.Docs.example(),
        positional: [
          file: [optional: true],
          packages: [rest: true, optional: true]
        ],
        schema: [
          all: :boolean,
          list: :boolean,
          remove: :boolean,
          remove_missing: :boolean,
          link_to_folder: :string,
          link_style: :string,
          inline: :string,
          folder_only: :string,
          merge_sub_rules: :boolean
        ]
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

      # Add all usage-rules.md files and usage_rules/ folders from deps directory to igniter
      igniter =
        igniter
        |> Igniter.include_glob("deps/*/usage-rules.md")
        |> Igniter.include_glob("deps/*/usage_rules/*.md")

      top_level_deps =
        Mix.Project.get().project()[:deps] |> Enum.map(&elem(&1, 0))

      # Get all deps from both Mix.Project.deps_paths and Igniter rewrite sources
      mix_deps =
        Mix.Project.deps_paths()
        |> Enum.filter(fn {dep, _path} ->
          dep in top_level_deps
        end)
        |> Enum.map(fn {dep, path} ->
          {dep, Path.relative_to_cwd(path)}
        end)

      igniter_deps = get_deps_from_igniter(igniter)
      all_deps = (mix_deps ++ igniter_deps) |> Enum.uniq()

      all_option = igniter.args.options[:all]
      list_option = igniter.args.options[:list]
      remove_option = igniter.args.options[:remove]
      remove_missing_option = igniter.args.options[:remove_missing]
      link_to_folder = igniter.args.options[:link_to_folder]
      link_style = igniter.args.options[:link_style] || "markdown"
      inline_specs = parse_inline_specs(igniter.args.options[:inline])
      folder_only = igniter.args.options[:folder_only]
      merge_sub_rules = igniter.args.options[:merge_sub_rules] || false
      # Fix argument parsing for folder-only: when no file should be specified,
      # the first argument gets incorrectly parsed as 'file' instead of the first package
      provided_packages =
        if folder_only && igniter.args.positional[:file] &&
             !File.exists?(igniter.args.positional[:file]) do
          # The 'file' is actually the first package
          [igniter.args.positional[:file]] ++ (igniter.args.positional.packages || [])
        else
          igniter.args.positional.packages || []
        end

      cond do
        # If --link-style is used with invalid value, add error
        link_style && link_style not in ["markdown", "at"] ->
          Igniter.add_issue(igniter, "--link-style must be either 'markdown' or 'at'")

        # If --link-style is used without --link-to-folder, add error
        igniter.args.options[:link_style] && !link_to_folder ->
          Igniter.add_issue(igniter, "--link-style can only be used with --link-to-folder")

        # If --merge-sub-rules is used without --folder-only, add error
        merge_sub_rules && !folder_only ->
          Igniter.add_issue(igniter, "--merge-sub-rules can only be used with --folder-only")

        # If --folder-only is used with incompatible options, add error
        folder_only && (list_option || remove_option || remove_missing_option || link_to_folder) ->
          Igniter.add_issue(
            igniter,
            "--folder-only cannot be used with --list, --remove, --remove-missing, or --link-to-folder options"
          )

        # If --folder-only is used without packages and not with --all, add error
        folder_only && Enum.empty?(provided_packages) && !all_option ->
          Igniter.add_issue(
            igniter,
            "--folder-only requires either --all or specific packages to be provided"
          )

        # If --remove is used with --all or --list, add error
        remove_option && (all_option || list_option) ->
          Igniter.add_issue(igniter, "Cannot use --remove with --all or --list options")

        # If --remove-missing is used without a file, add error
        remove_missing_option && is_nil(igniter.args.positional[:file]) ->
          Igniter.add_issue(igniter, "--remove-missing option requires a file to modify")

        # If --remove-missing is used with --list, add error
        remove_missing_option && list_option ->
          Igniter.add_issue(igniter, "Cannot use --remove-missing with --list option")

        # If --remove is used without a file, add error
        remove_option && is_nil(igniter.args.positional[:file]) ->
          Igniter.add_issue(igniter, "--remove option requires a file to remove from")

        # If --remove is used without packages, add error
        remove_option && Enum.empty?(provided_packages) ->
          Igniter.add_issue(igniter, "--remove option requires packages to remove")

        # If --list is given and packages list is not empty, add error
        list_option && !Enum.empty?(provided_packages) ->
          Igniter.add_issue(igniter, "Cannot specify packages when using --list option")

        # If --all is given and packages list is not empty (except with --folder-only), add error
        all_option && !Enum.empty?(provided_packages) && !folder_only ->
          Igniter.add_issue(igniter, "Cannot specify packages when using --all option")

        # If --all is used without a file (and not with --folder-only), add error
        all_option && is_nil(igniter.args.positional[:file]) && !folder_only ->
          Igniter.add_issue(igniter, "--all option requires a file to write to")

        # If --link-to-folder is used without a file, add error
        link_to_folder && is_nil(igniter.args.positional[:file]) ->
          Igniter.add_issue(igniter, "--link-to-folder option requires a file to write to")

        # If no packages are given and neither --list nor --all nor --remove nor --remove-missing nor --folder-only is set, add error
        Enum.empty?(provided_packages) && !all_option && !list_option && !remove_option &&
          !remove_missing_option && !folder_only ->
          add_usage_error(igniter)

        # Handle --folder-only option
        folder_only ->
          handle_folder_only_option(
            igniter,
            all_deps,
            provided_packages,
            folder_only,
            all_option,
            merge_sub_rules
          )

        # Handle --remove option
        remove_option ->
          handle_remove_packages(igniter, provided_packages, link_to_folder)

        # Handle --all option
        all_option ->
          handle_all_option(
            igniter,
            all_deps,
            link_to_folder,
            link_style,
            inline_specs,
            remove_missing_option
          )

        # Handle --list option
        list_option ->
          handle_list_option(igniter, all_deps, link_to_folder, link_style, inline_specs)

        # Handle specific packages
        true ->
          handle_specific_packages(
            igniter,
            all_deps,
            provided_packages,
            link_to_folder,
            link_style,
            inline_specs,
            remove_missing_option
          )
      end
      |> notice_about_all_option(all_option)
    end

    defp notice_about_all_option(igniter, all_option) do
      file = igniter.args.positional[:file]

      if all_option do
        Igniter.add_warning(igniter, """
        Usage Rules:

        We've synchronized usage rules for all of your direct
        dependencies into #{file}. When working with agents, it
        is important to manage your context window. Consider
        which packages you wish to have present. You can use
        the `--remove-missing` flag to select exactly what to sync.

        For example:

            mix usage_rules.sync #{file} pkg1 pkg2 \\
              usage_rules:all \\
              --inline usage_rules:all \\
              --link-to-folder deps \\
              --remove-missing
        """)
      else
        igniter
      end
    end

    defp usage_rules_header do
      """
      <!-- usage-rules-header -->
      # Usage Rules

      **IMPORTANT**: Consult these usage rules early and often when working with the packages listed below. 
      Before attempting to use any of these packages or to discover if you should use them, review their 
      usage rules to understand the correct patterns, conventions, and best practices.
      <!-- usage-rules-header-end -->
      """
    end

    defp get_package_description(name) do
      case Application.spec(name, :description) do
        nil -> ""
        desc -> String.trim_trailing(to_string(desc))
      end
    end

    defp get_deps_from_igniter(igniter) do
      if igniter.assigns[:test_mode?] do
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.match?(path, ~r|^deps/[^/]+/usage-rules\.md$|) ||
            String.match?(path, ~r|^deps/[^/]+/usage-rules/[^/]+\.md$|)
        end)
        |> Enum.map(fn {path, _source} ->
          # Extract package name from deps/package_name/usage-rules.md or deps/package_name/usage-rules/sub-rule.md
          package_name =
            path
            |> String.split("/")
            |> Enum.at(1)
            |> String.to_atom()

          # Extract package path from deps/package_name/...
          package_path = Path.join("deps", to_string(package_name))

          {package_name, package_path}
        end)
        |> Enum.uniq()
      else
        []
      end
    end

    defp parse_package_spec(package_spec) when is_binary(package_spec) do
      case String.split(package_spec, ":", parts: 2) do
        [package_name] ->
          {String.to_atom(package_name), nil}

        [package_name, sub_rule] ->
          {String.to_atom(package_name), sub_rule}
      end
    end

    defp find_available_sub_rules(igniter, package_path) do
      usage_rules_dir = Path.join(package_path, "usage-rules")

      # Try to find sub-rules from igniter sources first (works in both test and regular mode)
      source_sub_rules =
        igniter.rewrite.sources
        |> Enum.filter(fn {path, _source} ->
          String.starts_with?(path, usage_rules_dir <> "/") &&
            String.ends_with?(path, ".md")
        end)
        |> Enum.map(fn {path, _source} ->
          path
          |> Path.basename()
          |> Path.rootname()
        end)
        |> Enum.sort()

      # If we found sub-rules in sources, return them
      if Enum.any?(source_sub_rules) do
        source_sub_rules
      else
        # Otherwise, try file system
        case File.ls(usage_rules_dir) do
          {:ok, files} ->
            files
            |> Enum.filter(&String.ends_with?(&1, ".md"))
            |> Enum.map(&Path.rootname/1)
            |> Enum.sort()

          {:error, _} ->
            []
        end
      end
    end

    defp parse_inline_specs(nil), do: []

    defp parse_inline_specs(inline_string) do
      inline_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end

    defp should_inline_package?(package_name, sub_rule, inline_specs) do
      package_name_str = to_string(package_name)

      section_name =
        case sub_rule do
          nil -> package_name_str
          sub_rule_name -> "#{package_name_str}:#{sub_rule_name}"
        end

      Enum.any?(inline_specs, fn inline_spec ->
        case String.split(inline_spec, ":", parts: 2) do
          [^package_name_str] when sub_rule == nil ->
            true

          [^package_name_str, "all"] ->
            true

          [^package_name_str, sub_rule_spec] when sub_rule == sub_rule_spec ->
            true

          [^section_name] ->
            true

          # Special case: "usage_rules:all" means inline all sub-rules
          ["usage_rules", "all"] when sub_rule != nil ->
            true

          _ ->
            false
        end
      end)
    end

    defp expand_wildcard_specs(igniter, all_deps, provided_packages) do
      Enum.flat_map(provided_packages, fn package_spec ->
        {package_name, sub_rule} = parse_package_spec(package_spec)

        case sub_rule do
          "all" ->
            # Find the package path
            case Enum.find(all_deps, fn {name, _path} -> name == package_name end) do
              {_name, package_path} ->
                available_sub_rules = find_available_sub_rules(igniter, package_path)

                Enum.map(available_sub_rules, fn sub_rule_name ->
                  "#{package_name}:#{sub_rule_name}"
                end)

              nil ->
                [package_spec]
            end

          _ ->
            [package_spec]
        end
      end)
    end

    defp add_usage_error(igniter) do
      Igniter.add_issue(igniter, """
      Usage:
        mix usage_rules.sync CLAUDE.md --all --link-to-folder deps
          Standard usage: gather all dependencies and link directly to deps files

        mix usage_rules.sync <file> <packages...>
          Combine specific packages' usage rules into the target file

        mix usage_rules.sync <file> --all
          Gather usage rules from all dependencies into the target file

        mix usage_rules.sync [file] --list
          List packages with usage rules (optionally check status against file)

        mix usage_rules.sync <file> <packages...> --remove
          Remove specific packages from the target file

        mix usage_rules.sync <file> <packages...> --link-to-folder <folder>
          Save usage rules for each package in separate files within the specified folder and create links to them

        mix usage_rules.sync <file> --list --link-to-folder <folder>
          List packages with usage rules and check status against folder links

        mix usage_rules.sync <file> <packages...> --remove --link-to-folder <folder>
          Remove specific packages from the target file and delete their folder files

        mix usage_rules.sync <packages...> --folder-only <folder>
          Extract usage rules for specific packages to the specified folder without updating any other files

        mix usage_rules.sync --all --folder-only <folder>
          Extract usage rules for all dependencies to the specified folder without updating any other files

        mix usage_rules.sync <packages...> --folder-only <folder> --merge-sub-rules
          Extract usage rules for specific packages to the specified folder, merging sub-rules into single files

        mix usage_rules.sync --all --folder-only <folder> --merge-sub-rules
          Extract usage rules for all dependencies to the specified folder, merging sub-rules into single files
      """)
    end

    defp handle_all_option(
           igniter,
           all_deps,
           link_to_folder,
           link_style,
           inline_specs,
           remove_missing
         ) do
      all_packages_with_rules = get_packages_with_usage_rules(igniter, all_deps)

      # Discover all package rules including sub-rules
      all_package_rules =
        all_packages_with_rules
        |> Enum.flat_map(fn {package_name, package_path} ->
          # Check for main usage-rules.md file
          main_rules =
            if Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
              [{package_name, package_path, nil}]
            else
              []
            end

          # Check for sub-rules in usage_rules/ folder
          sub_rules =
            find_available_sub_rules(igniter, package_path)
            |> Enum.map(fn sub_rule_name ->
              {package_name, package_path, sub_rule_name}
            end)

          main_rules ++ sub_rules
        end)

      igniter
      |> Igniter.add_notice(
        "Found #{length(all_packages_with_rules)} dependencies with usage rules"
      )
      |> then(fn igniter ->
        Enum.reduce(all_package_rules, igniter, fn {name, _path, sub_rule}, acc ->
          case sub_rule do
            nil ->
              Igniter.add_notice(acc, "Including usage rules for: #{name}")

            sub_rule_name ->
              Igniter.add_notice(acc, "Including usage rules for: #{name}:#{sub_rule_name}")
          end
        end)
      end)
      |> generate_usage_rules_file(
        all_package_rules,
        link_to_folder,
        link_style,
        inline_specs,
        remove_missing
      )
    end

    defp handle_list_option(igniter, all_deps, link_to_folder, link_style, inline_specs) do
      packages_with_rules = get_packages_with_usage_rules(igniter, all_deps)

      if Enum.empty?(packages_with_rules) do
        Igniter.add_notice(igniter, "No packages found with usage-rules.md files")
      else
        file_path = igniter.args.positional[:file]

        if file_path do
          list_packages_with_file_comparison(
            igniter,
            packages_with_rules,
            file_path,
            link_to_folder,
            link_style,
            inline_specs
          )
        else
          list_packages_without_comparison(igniter, packages_with_rules)
        end
      end
    end

    defp handle_specific_packages(
           igniter,
           all_deps,
           provided_packages,
           link_to_folder,
           link_style,
           inline_specs,
           remove_missing
         ) do
      # Expand wildcard specs first
      expanded_packages = expand_wildcard_specs(igniter, all_deps, provided_packages)

      # Parse and process each package spec
      package_rules =
        expanded_packages
        |> Enum.flat_map(fn package_spec ->
          {package_name, sub_rule} = parse_package_spec(package_spec)

          case Enum.find(all_deps, fn {name, _path} -> name == package_name end) do
            {_name, package_path} ->
              case sub_rule do
                nil ->
                  # Standard package without sub-rule - check for usage-rules.md
                  usage_rules_path = Path.join(package_path, "usage-rules.md")

                  if Igniter.exists?(igniter, usage_rules_path) do
                    [{package_name, package_path, nil}]
                  else
                    []
                  end

                sub_rule_name ->
                  # Sub-rule specified - check for usage-rules/sub_rule.md
                  sub_rule_path = Path.join([package_path, "usage-rules", "#{sub_rule_name}.md"])

                  if Igniter.exists?(igniter, sub_rule_path) do
                    [{package_name, package_path, sub_rule_name}]
                  else
                    []
                  end
              end

            nil ->
              []
          end
        end)

      igniter
      |> generate_usage_rules_file(
        package_rules,
        link_to_folder,
        link_style,
        inline_specs,
        remove_missing
      )
    end

    defp handle_remove_packages(igniter, provided_packages, link_to_folder) do
      file_path = igniter.args.positional[:file]

      if Igniter.exists?(igniter, file_path) do
        remove_packages_from_file(igniter, file_path, provided_packages, link_to_folder)
      else
        Igniter.add_issue(igniter, "File #{file_path} does not exist")
      end
    end

    defp handle_folder_only_option(
           igniter,
           all_deps,
           provided_packages,
           folder_name,
           all_option,
           merge_sub_rules
         ) do
      packages_to_process =
        if all_option do
          all_packages_with_rules = get_packages_with_usage_rules(igniter, all_deps)

          all_packages_with_rules
          |> Enum.flat_map(fn {package_name, package_path} ->
            main_rules =
              if Igniter.exists?(igniter, Path.join(package_path, "usage-rules.md")) do
                [{package_name, package_path, nil}]
              else
                []
              end

            sub_rules =
              find_available_sub_rules(igniter, package_path)
              |> Enum.map(fn sub_rule_name ->
                {package_name, package_path, sub_rule_name}
              end)

            main_rules ++ sub_rules
          end)
        else
          expanded_packages = expand_wildcard_specs(igniter, all_deps, provided_packages)

          expanded_packages
          |> Enum.flat_map(fn package_spec ->
            {package_name, sub_rule} = parse_package_spec(package_spec)

            case Enum.find(all_deps, fn {name, _path} -> name == package_name end) do
              {_name, package_path} ->
                case sub_rule do
                  nil ->
                    usage_rules_path = Path.join(package_path, "usage-rules.md")

                    if Igniter.exists?(igniter, usage_rules_path) do
                      [{package_name, package_path, nil}]
                    else
                      []
                    end

                  sub_rule_name ->
                    sub_rule_path =
                      Path.join([package_path, "usage-rules", "#{sub_rule_name}.md"])

                    if Igniter.exists?(igniter, sub_rule_path) do
                      [{package_name, package_path, sub_rule_name}]
                    else
                      []
                    end
                end

              nil ->
                []
            end
          end)
        end

      if merge_sub_rules do
        # Merge sub-rules into single files per package
        packages_to_process
        |> Enum.group_by(fn {name, _path, _sub_rule} -> name end)
        |> Enum.reduce(igniter, fn {package_name, rules}, acc ->
          target_file_name = "#{package_name}.md"
          package_file_path = Path.join(folder_name, target_file_name)

          package_contents =
            rules
            |> Enum.map(fn {_name, path, sub_rule} ->
              usage_rules_path =
                case sub_rule do
                  nil ->
                    Path.join(path, "usage-rules.md")

                  sub_rule_name ->
                    Path.join([path, "usage-rules", "#{sub_rule_name}.md"])
                end

              content =
                case Rewrite.source(acc.rewrite, usage_rules_path) do
                  {:ok, source} -> Rewrite.Source.get(source, :content)
                  {:error, _} -> File.read!(usage_rules_path)
                end

              section_name =
                case sub_rule do
                  nil -> to_string(package_name)
                  sub_rule_name -> "#{package_name}:#{sub_rule_name}"
                end

              description =
                case sub_rule do
                  nil -> get_package_description(package_name)
                  _ -> ""
                end

              description_part = if description == "", do: "", else: "_#{description}_\n\n"

              {section_name,
               "<!-- #{section_name}-start -->\n" <>
                 "## #{section_name} usage\n" <>
                 description_part <>
                 content <>
                 "\n<!-- #{section_name}-end -->"}
            end)

          all_rules_content = Enum.map_join(package_contents, "\n", &elem(&1, 1))

          full_contents_for_new_file = all_rules_content

          section_names =
            rules
            |> Enum.map(fn {_name, _path, sub_rule} ->
              case sub_rule do
                nil -> to_string(package_name)
                sub_rule_name -> "#{package_name}:#{sub_rule_name}"
              end
            end)
            |> Enum.join(", ")

          acc
          |> Igniter.add_notice(
            "Extracting and merging usage rules for: #{section_names} -> #{package_file_path}"
          )
          |> Igniter.create_or_update_file(
            package_file_path,
            full_contents_for_new_file,
            fn source ->
              current_contents = Rewrite.Source.get(source, :content)

              new_content =
                if current_contents == "" do
                  # New file, just concatenate all package contents
                  Enum.map_join(package_contents, "\n", &elem(&1, 1))
                else
                  # Existing file, update each section
                  Enum.reduce(package_contents, current_contents, fn {name, package_content},
                                                                     acc_content ->
                    case String.split(acc_content, [
                           "<!-- #{name}-start -->\n",
                           "\n<!-- #{name}-end -->"
                         ]) do
                      [prelude, _, postlude] ->
                        prelude <> package_content <> postlude

                      _ ->
                        acc_content <> "\n" <> package_content
                    end
                  end)
                end

              Rewrite.Source.update(source, :content, new_content)
            end
          )
        end)
      else
        # Create separate files for each package and sub-rule
        Enum.reduce(packages_to_process, igniter, fn {name, path, sub_rule}, acc ->
          {usage_rules_path, target_file_name} =
            case sub_rule do
              nil ->
                {Path.join(path, "usage-rules.md"), "#{name}.md"}

              sub_rule_name ->
                {Path.join([path, "usage-rules", "#{sub_rule_name}.md"]),
                 "#{name}_#{sub_rule_name}.md"}
            end

          content =
            case Rewrite.source(acc.rewrite, usage_rules_path) do
              {:ok, source} -> Rewrite.Source.get(source, :content)
              {:error, _} -> File.read!(usage_rules_path)
            end

          package_file_path = Path.join(folder_name, target_file_name)

          section_name =
            case sub_rule do
              nil -> to_string(name)
              sub_rule_name -> "#{name}:#{sub_rule_name}"
            end

          acc
          |> Igniter.add_notice(
            "Extracting usage rules for: #{section_name} -> #{package_file_path}"
          )
          |> Igniter.create_or_update_file(
            package_file_path,
            content,
            fn source ->
              Rewrite.Source.update(source, :content, content)
            end
          )
        end)
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

    defp list_packages_with_file_comparison(
           igniter,
           packages_with_rules,
           file_path,
           link_to_folder,
           link_style,
           inline_specs
         ) do
      current_file_content = read_current_file_content(igniter, file_path)

      Enum.reduce(packages_with_rules, igniter, fn {name, path}, acc ->
        # Ensure name is a string
        name = to_string(name)

        # Check for main package and sub-rules
        usage_rules_path = Path.join(path, "usage-rules.md")
        has_main = Igniter.exists?(acc, usage_rules_path)
        sub_rules = find_available_sub_rules(igniter, path)

        # Build the notice message
        message_parts = []

        # Add main package status if exists
        message_parts =
          if has_main do
            package_rules_content =
              case Rewrite.source(acc.rewrite, usage_rules_path) do
                {:ok, source} -> Rewrite.Source.get(source, :content)
                {:error, _} -> File.read!(usage_rules_path)
              end

            status =
              get_package_status_in_file(
                acc,
                name,
                package_rules_content,
                current_file_content,
                link_to_folder,
                link_style,
                inline_specs
              )

            ["  #{name} - #{colorize_status(status)}" | message_parts]
          else
            message_parts
          end

        # Add sub-rules status if any
        message_parts =
          if Enum.any?(sub_rules) do
            sub_rule_lines =
              sub_rules
              |> Enum.filter(fn sub_rule_name ->
                sub_rule_path = Path.join([path, "usage-rules", "#{sub_rule_name}.md"])
                Igniter.exists?(acc, sub_rule_path)
              end)
              |> Enum.map(fn sub_rule_name ->
                sub_rule_path = Path.join([path, "usage-rules", "#{sub_rule_name}.md"])

                sub_rule_content =
                  case Rewrite.source(acc.rewrite, sub_rule_path) do
                    {:ok, source} -> Rewrite.Source.get(source, :content)
                    {:error, _} -> File.read!(sub_rule_path)
                  end

                sub_status =
                  get_package_status_in_file(
                    acc,
                    "#{name}:#{sub_rule_name}",
                    sub_rule_content,
                    current_file_content,
                    link_to_folder,
                    link_style,
                    inline_specs
                  )

                "  #{name}:#{sub_rule_name} - #{colorize_status(sub_status)}"
              end)

            message_parts ++ sub_rule_lines
          else
            message_parts
          end

        # Add the combined notice if we have anything to show
        if Enum.any?(message_parts) do
          # For file comparison, don't add the standalone package name
          full_message = Enum.join([name | Enum.reverse(message_parts)], "\n")
          Igniter.add_notice(acc, full_message)
        else
          acc
        end
      end)
    end

    defp list_packages_without_comparison(igniter, packages_with_rules) do
      Enum.reduce(packages_with_rules, igniter, fn {package_name, package_path}, acc ->
        # Ensure name is a string
        package_name = to_string(package_name)

        # Check for main package and sub-rules
        usage_rules_path = Path.join(package_path, "usage-rules.md")
        has_main = Igniter.exists?(acc, usage_rules_path)
        available_sub_rules = find_available_sub_rules(igniter, package_path)

        # Build message lines for this specific package
        lines = []

        # Add main package line if it exists
        lines =
          if has_main do
            ["  #{package_name} - #{IO.ANSI.green()}has usage rules#{IO.ANSI.green()}"] ++ lines
          else
            lines
          end

        # Add sub-rules lines if they exist
        lines =
          if Enum.any?(available_sub_rules) do
            valid_sub_rules =
              available_sub_rules
              |> Enum.filter(fn sub_rule_name ->
                sub_rule_path = Path.join([package_path, "usage-rules", "#{sub_rule_name}.md"])
                Igniter.exists?(acc, sub_rule_path)
              end)
              |> Enum.sort()

            sub_rule_lines =
              Enum.map(valid_sub_rules, fn sub_rule_name ->
                "  #{package_name}:#{sub_rule_name} - #{IO.ANSI.green()}has sub-rule#{IO.ANSI.green()}"
              end)

            lines ++ sub_rule_lines
          else
            lines
          end

        # Add notice for this package if we have anything to show
        if Enum.any?(lines) do
          message = Enum.join([package_name | Enum.reverse(lines)], "\n")
          Igniter.add_notice(acc, message)
        else
          acc
        end
      end)
    end

    defp read_current_file_content(igniter, file_path) do
      if Igniter.exists?(igniter, file_path) do
        case Rewrite.source(igniter.rewrite, file_path) do
          {:ok, source} ->
            Rewrite.Source.get(source, :content)

          {:error, _} ->
            case File.read(file_path) do
              {:ok, content} -> content
              {:error, _} -> ""
            end
        end
      else
        ""
      end
    end

    defp generate_usage_rules_file(
           igniter,
           packages,
           link_to_folder,
           link_style,
           inline_specs,
           remove_missing
         ) do
      if link_to_folder do
        generate_usage_rules_with_folder_links(
          igniter,
          packages,
          link_to_folder,
          link_style,
          inline_specs,
          remove_missing
        )
      else
        generate_usage_rules_inline(igniter, packages, remove_missing)
      end
    end

    defp extract_existing_package_names(content) do
      # Extract package names from <!-- package-name-start --> markers
      Regex.scan(~r/<!-- ([^-]+(?::[^-]+)?)-start -->/, content, capture: :all_but_first)
      |> Enum.map(fn [name] -> name end)
    end

    defp remove_missing_packages_from_content(content, packages_to_keep) do
      existing_packages = extract_existing_package_names(content)
      packages_to_remove = existing_packages -- packages_to_keep

      Enum.reduce(packages_to_remove, content, fn package_name, acc ->
        case String.split(acc, [
               "<!-- #{package_name}-start -->\n",
               "\n<!-- #{package_name}-end -->"
             ]) do
          [prelude, _, postlude] ->
            # Remove the package section, keeping proper spacing
            prelude <> postlude

          _ ->
            acc
        end
      end)
    end

    defp update_usage_rules_content(current_packages_contents, package_contents, remove_missing) do
      # Apply remove_missing logic if requested
      cleaned_content =
        if remove_missing do
          packages_to_keep = Enum.map(package_contents, fn {name, _} -> name end)
          remove_missing_packages_from_content(current_packages_contents, packages_to_keep)
        else
          current_packages_contents
        end

      Enum.reduce(package_contents, cleaned_content, fn {name, package_content}, acc ->
        case String.split(acc, [
               "<!-- #{name}-start -->\n",
               "\n<!-- #{name}-end -->"
             ]) do
          [prelude, _, postlude] ->
            prelude <> package_content <> postlude

          _ ->
            acc <> "\n" <> package_content
        end
      end)
    end

    defp generate_usage_rules_inline(igniter, packages, remove_missing) do
      package_contents =
        packages
        |> Enum.map(fn {name, path, sub_rule} ->
          {usage_rules_path, section_name} =
            case sub_rule do
              nil ->
                {Path.join(path, "usage-rules.md"), to_string(name)}

              sub_rule_name ->
                {Path.join([path, "usage-rules", "#{sub_rule_name}.md"]),
                 "#{name}:#{sub_rule_name}"}
            end

          content =
            case Rewrite.source(igniter.rewrite, usage_rules_path) do
              {:ok, source} -> Rewrite.Source.get(source, :content)
              {:error, _} -> File.read!(usage_rules_path)
            end

          description =
            case sub_rule do
              nil -> get_package_description(name)
              # Sub-rules don't get package descriptions
              _ -> ""
            end

          description_part = if description == "", do: "", else: "_#{description}_\n\n"

          {section_name,
           "<!-- #{section_name}-start -->\n" <>
             "## #{section_name} usage\n" <>
             description_part <>
             content <>
             "\n<!-- #{section_name}-end -->"}
        end)

      all_rules_content = Enum.map_join(package_contents, "\n", &elem(&1, 1))

      full_contents_for_new_file =
        "<!-- usage-rules-start -->\n" <>
          usage_rules_header() <>
          "\n" <>
          all_rules_content <>
          "\n<!-- usage-rules-end -->"

      Igniter.create_or_update_file(
        igniter,
        igniter.args.positional[:file],
        full_contents_for_new_file,
        fn source ->
          current_contents = Rewrite.Source.get(source, :content)

          new_content =
            case String.split(current_contents, [
                   "<!-- usage-rules-start -->\n",
                   "\n<!-- usage-rules-end -->"
                 ]) do
              [prelude, current_packages_contents, postlude] ->
                update_usage_rules_content(
                  current_packages_contents,
                  package_contents,
                  remove_missing
                )
                |> then(fn content ->
                  # Ensure header is present
                  content_with_header =
                    if String.contains?(content, "<!-- usage-rules-header -->") do
                      content
                    else
                      usage_rules_header() <> "\n" <> content
                    end

                  prelude <>
                    "<!-- usage-rules-start -->\n" <>
                    content_with_header <>
                    "\n<!-- usage-rules-end -->" <>
                    postlude
                end)

              _ ->
                current_contents <>
                  "\n<!-- usage-rules-start -->\n" <>
                  usage_rules_header() <>
                  "\n" <>
                  all_rules_content <>
                  "\n<!-- usage-rules-end -->\n"
            end

          Rewrite.Source.update(source, :content, new_content)
        end
      )
    end

    defp generate_usage_rules_with_folder_links(
           igniter,
           packages,
           folder_name,
           link_style,
           inline_specs,
           remove_missing
         ) do
      # Create individual files for each package in the folder (unless folder is "deps")
      igniter =
        if folder_name == "deps" do
          igniter
        else
          Enum.reduce(packages, igniter, fn {name, path, sub_rule}, acc ->
            # Skip creating files for packages that should be inlined
            if should_inline_package?(name, sub_rule, inline_specs) do
              acc
            else
              {usage_rules_path, target_file_name} =
                case sub_rule do
                  nil ->
                    {Path.join(path, "usage-rules.md"), "#{name}.md"}

                  sub_rule_name ->
                    {Path.join([path, "usage-rules", "#{sub_rule_name}.md"]),
                     "#{name}_#{sub_rule_name}.md"}
                end

              content =
                case Rewrite.source(acc.rewrite, usage_rules_path) do
                  {:ok, source} -> Rewrite.Source.get(source, :content)
                  {:error, _} -> File.read!(usage_rules_path)
                end

              package_file_path = Path.join(folder_name, target_file_name)

              Igniter.create_or_update_file(
                acc,
                package_file_path,
                content,
                fn source ->
                  Rewrite.Source.update(source, :content, content)
                end
              )
            end
          end)
        end

      # Then, create the main file with links or inline content
      package_contents =
        packages
        |> Enum.map(fn {name, path, sub_rule} ->
          section_name =
            case sub_rule do
              nil -> to_string(name)
              sub_rule_name -> "#{name}:#{sub_rule_name}"
            end

          description =
            case sub_rule do
              nil -> get_package_description(name)
              # Sub-rules don't get package descriptions
              _ -> ""
            end

          description_part = if description == "", do: "", else: "_#{description}_\n\n"

          content =
            if should_inline_package?(name, sub_rule, inline_specs) do
              # Inline the actual content
              {usage_rules_path, _} =
                case sub_rule do
                  nil ->
                    {Path.join(path, "usage-rules.md"), "#{name}.md"}

                  sub_rule_name ->
                    {Path.join([path, "usage-rules", "#{sub_rule_name}.md"]),
                     "#{name}_#{sub_rule_name}.md"}
                end

              case Rewrite.source(igniter.rewrite, usage_rules_path) do
                {:ok, source} -> Rewrite.Source.get(source, :content)
                {:error, _} -> File.read!(usage_rules_path)
              end
            else
              # Create link
              case sub_rule do
                nil ->
                  case {link_style, folder_name} do
                    {"at", "deps"} -> "@deps/#{name}/usage-rules.md"
                    {"at", _} -> "@#{folder_name}/#{name}.md"
                    {_, "deps"} -> "[#{name} usage rules](deps/#{name}/usage-rules.md)"
                    _ -> "[#{name} usage rules](#{folder_name}/#{name}.md)"
                  end

                sub_rule_name ->
                  case {link_style, folder_name} do
                    {"at", "deps"} ->
                      "@deps/#{name}/usage-rules/#{sub_rule_name}.md"

                    {"at", _} ->
                      "@#{folder_name}/#{name}_#{sub_rule_name}.md"

                    {_, "deps"} ->
                      "[#{section_name} usage rules](deps/#{name}/usage-rules/#{sub_rule_name}.md)"

                    _ ->
                      "[#{section_name} usage rules](#{folder_name}/#{name}_#{sub_rule_name}.md)"
                  end
              end
            end

          {section_name,
           "<!-- #{section_name}-start -->\n" <>
             "## #{section_name} usage\n" <>
             description_part <>
             content <>
             "\n<!-- #{section_name}-end -->"}
        end)

      all_rules_content = Enum.map_join(package_contents, "\n", &elem(&1, 1))

      full_contents_for_new_file =
        "<!-- usage-rules-start -->\n" <>
          usage_rules_header() <>
          "\n" <>
          all_rules_content <>
          "\n<!-- usage-rules-end -->"

      Igniter.create_or_update_file(
        igniter,
        igniter.args.positional[:file],
        full_contents_for_new_file,
        fn source ->
          current_contents = Rewrite.Source.get(source, :content)

          new_content =
            case String.split(current_contents, [
                   "<!-- usage-rules-start -->\n",
                   "\n<!-- usage-rules-end -->"
                 ]) do
              [prelude, current_packages_contents, postlude] ->
                update_usage_rules_content(
                  current_packages_contents,
                  package_contents,
                  remove_missing
                )
                |> then(fn content ->
                  # Ensure header is present
                  content_with_header =
                    if String.contains?(content, "<!-- usage-rules-header -->") do
                      content
                    else
                      usage_rules_header() <> "\n" <> content
                    end

                  prelude <>
                    "<!-- usage-rules-start -->\n" <>
                    content_with_header <>
                    "\n<!-- usage-rules-end -->" <>
                    postlude
                end)

              _ ->
                current_contents <>
                  "\n<!-- usage-rules-start -->\n" <>
                  usage_rules_header() <>
                  "\n" <>
                  all_rules_content <>
                  "\n<!-- usage-rules-end -->\n"
            end

          Rewrite.Source.update(source, :content, new_content)
        end
      )
    end

    defp remove_packages_from_file(igniter, file_path, packages_to_remove, link_to_folder) do
      # If using link-to-folder, also remove the individual package files
      igniter =
        if link_to_folder do
          Enum.reduce(packages_to_remove, igniter, fn package_name, acc ->
            package_file_path = Path.join(link_to_folder, "#{package_name}.md")

            if Igniter.exists?(acc, package_file_path) do
              Igniter.rm(acc, package_file_path)
            else
              acc
            end
          end)
        else
          igniter
        end

      Igniter.update_file(igniter, file_path, fn source ->
        current_contents = Rewrite.Source.get(source, :content)

        new_content =
          Enum.reduce(packages_to_remove, current_contents, fn package_name, acc ->
            remove_package_from_content(acc, package_name)
          end)
          |> clean_empty_package_rules_section()

        Rewrite.Source.update(source, :content, new_content)
      end)
    end

    defp remove_package_from_content(content, package_name) do
      package_start_marker = "<!-- #{package_name}-start -->\n"
      package_end_marker = "\n<!-- #{package_name}-end -->"

      case String.split(content, [package_start_marker, package_end_marker]) do
        [prelude, _package_content, postlude] ->
          # Remove the package section completely, handling newlines properly
          cleaned_prelude = String.trim_trailing(prelude)
          cleaned_postlude = String.trim_leading(postlude)

          if cleaned_postlude == "" do
            cleaned_prelude
          else
            cleaned_prelude <> "\n" <> cleaned_postlude
          end

        _ ->
          # Package not found, return content unchanged
          content
      end
    end

    defp clean_empty_package_rules_section(content) do
      # Handle both cases: empty section and section with only whitespace
      case String.split(content, "<!-- usage-rules-start -->") do
        [prelude, remainder] ->
          case String.split(remainder, "<!-- usage-rules-end -->") do
            [package_section, postlude] ->
              # Check if package section is empty or only contains whitespace
              if String.trim(package_section) == "" do
                # Remove the entire usage-rules section if empty
                cleaned_prelude = String.trim_trailing(prelude)
                cleaned_postlude = String.trim_leading(postlude)

                if cleaned_postlude == "" do
                  cleaned_prelude
                else
                  cleaned_prelude <> "\n\n" <> cleaned_postlude
                end
              else
                # Keep the usage-rules section
                prelude <>
                  "<!-- usage-rules-start -->" <>
                  package_section <> "<!-- usage-rules-end -->" <> postlude
              end

            _ ->
              # No end marker found
              content
          end

        _ ->
          # No usage-rules section found
          content
      end
    end

    defp get_package_status_in_file(
           igniter,
           name,
           package_rules_content,
           file_content,
           link_to_folder,
           link_style,
           inline_specs
         ) do
      package_start_marker = "<!-- #{name}-start -->"
      package_end_marker = "<!-- #{name}-end -->"

      case String.split(file_content, [package_start_marker, package_end_marker]) do
        [_, current_package_content, _] ->
          # Package is present in file, check if content matches
          {package_name, sub_rule} =
            case String.split(name, ":", parts: 2) do
              [l, r] -> {l, r}
              [l] -> {l, nil}
            end

          expected_content =
            if link_to_folder && !should_inline_package?(package_name, sub_rule, inline_specs) do
              # Generate the correct link format based on link_style
              link_content =
                case sub_rule do
                  nil ->
                    case {link_style, link_to_folder} do
                      {"at", "deps"} ->
                        "@deps/#{package_name}/usage-rules.md"

                      {"at", _} ->
                        "@#{link_to_folder}/#{package_name}.md"

                      {_, "deps"} ->
                        "[#{package_name} usage rules](deps/#{package_name}/usage-rules.md)"

                      _ ->
                        "[#{package_name} usage rules](#{link_to_folder}/#{package_name}.md)"
                    end

                  sub_rule_name ->
                    case {link_style, link_to_folder} do
                      {"at", "deps"} ->
                        "@deps/#{package_name}/usage-rules/#{sub_rule_name}.md"

                      {"at", _} ->
                        "@#{link_to_folder}/#{package_name}_#{sub_rule_name}.md"

                      {_, "deps"} ->
                        "[#{name} usage rules](deps/#{package_name}/usage-rules/#{sub_rule_name}.md)"

                      _ ->
                        "[#{name} usage rules](#{link_to_folder}/#{package_name}_#{sub_rule_name}.md)"
                    end
                end

              "\n## #{name} usage\n#{link_content}\n"
            else
              "\n## #{name} usage\n" <> package_rules_content <> "\n"
            end

          if String.trim(current_package_content) == String.trim(expected_content) do
            # If using link-to-folder, also check the linked file exists and matches
            if link_to_folder do
              check_linked_file_status(igniter, name, package_rules_content, link_to_folder)
            else
              "present"
            end
          else
            "stale"
          end

        _ ->
          # Package not found in file
          "missing"
      end
    end

    defp check_linked_file_status(igniter, name, expected_content, link_to_folder) do
      # Generate the correct file path based on package name and sub-rule
      {package_name, sub_rule} =
        case String.split(name, ":", parts: 2) do
          [l, r] -> {l, r}
          [l] -> {l, nil}
        end

      linked_file_path =
        case sub_rule do
          nil ->
            case link_to_folder do
              "deps" -> Path.join(["deps", package_name, "usage-rules.md"])
              _ -> Path.join(link_to_folder, "#{package_name}.md")
            end

          sub_rule_name ->
            case link_to_folder do
              "deps" ->
                Path.join(["deps", package_name, "usage-rules", "#{sub_rule_name}.md"])

              _ ->
                Path.join(link_to_folder, "#{package_name}_#{sub_rule_name}.md")
            end
        end

      if Igniter.exists?(igniter, linked_file_path) do
        actual_content =
          case Rewrite.source(igniter.rewrite, linked_file_path) do
            {:ok, source} ->
              Rewrite.Source.get(source, :content)

            {:error, _} ->
              if File.exists?(linked_file_path) do
                File.read!(linked_file_path)
              else
                ""
              end
          end

        if String.trim(actual_content) == String.trim(expected_content) do
          "present"
        else
          "stale"
        end
      else
        "stale"
      end
    end

    defp colorize_status("present"), do: "#{IO.ANSI.green()}present#{IO.ANSI.green()}"
    defp colorize_status("stale"), do: "#{IO.ANSI.yellow()}stale#{IO.ANSI.green()}"
    defp colorize_status("missing"), do: "#{IO.ANSI.red()}missing#{IO.ANSI.green()}"
  end
else
  defmodule Mix.Tasks.UsageRules.Sync do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'usage_rules.sync' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
