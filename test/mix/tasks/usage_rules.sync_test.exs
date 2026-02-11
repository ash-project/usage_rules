# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.SyncTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  defp sync(igniter, config) do
    igniter
    |> Igniter.assign(:test_mode?, true)
    |> Igniter.assign(:usage_rules_config, config)
    |> Igniter.compose_task("usage_rules.sync", [])
  end

  defp project_with_deps(files \\ %{}) do
    test_project(files: files)
  end

  defp file_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  describe "config validation" do
    test "errors when no config is provided" do
      project_with_deps()
      |> sync([])
      |> assert_has_issue(fn issue ->
        String.contains?(issue, "No usage_rules config found")
      end)
    end

    test "errors when config is not a keyword list" do
      project_with_deps()
      |> Igniter.assign(:test_mode?, true)
      |> Igniter.assign(:usage_rules_config, "bad")
      |> Igniter.compose_task("usage_rules.sync", [])
      |> assert_has_issue(fn issue ->
        String.contains?(issue, "usage_rules config must be a keyword list")
      end)
    end

    test "errors on invalid link option" do
      project_with_deps()
      |> sync(file: "AGENTS.md", usage_rules: [{:foo, link: :bad}])
      |> assert_has_issue(fn issue ->
        String.contains?(issue, "link must be :at or :markdown")
      end)
    end
  end

  describe "inline sync" do
    test "syncs a single package with usage-rules.md" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules\n\nUse foo wisely."
      })
      |> sync(file: "AGENTS.md", usage_rules: [:foo])
      |> assert_creates("AGENTS.md")
    end

    test "syncs multiple packages" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo, :bar])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "foo"
      assert content =~ "bar"
      assert content =~ "<!-- usage-rules-start -->"
      assert content =~ "<!-- usage-rules-end -->"
    end

    test "syncs with :all discovers all packages with usage rules" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules",
          "deps/no_rules/mix.exs" => "defmodule NoRules.MixProject, do: nil"
        })
        |> sync(file: "AGENTS.md", usage_rules: :all)
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "foo"
      assert content =~ "bar"
      refute content =~ "no_rules"
    end

    test "errors when a package is not a dependency" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules"
      })
      |> sync(file: "AGENTS.md", usage_rules: [:foo, :nonexistent])
      |> assert_has_issue(fn issue ->
        String.contains?(
          issue,
          "Package :nonexistent is listed in usage_rules but is not a dependency"
        )
      end)
    end

    test "errors when a package is not a dependency (no usage-rules files)" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules"
      })
      |> sync(file: "AGENTS.md", usage_rules: [:foo, :bar])
      |> assert_has_issue(fn issue ->
        String.contains?(
          issue,
          "Package :bar is listed in usage_rules but is not a dependency"
        )
      end)
    end

    test "includes sub-rules by default when using atom spec" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Main"
      assert content =~ "Foo Ecto"
      assert content =~ "Foo Testing"
    end

    test "package with only sub-rules (no main file) works" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Ecto"
    end

    test "strips SPDX comments from dependency content" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" =>
            "<!--\nSPDX-FileCopyrightText: 2025 foo contributors\nSPDX-License-Identifier: MIT\n-->\n\n# Foo Rules\n\nUse foo wisely."
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Rules"
      refute content =~ "SPDX"
    end
  end

  describe "builtin aliases" do
    test ":elixir resolves to usage_rules:elixir sub-rule" do
      igniter =
        project_with_deps(%{
          "deps/usage_rules/usage-rules/elixir.md" => "# Elixir Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:elixir])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Elixir Rules"
      assert content =~ "usage_rules:elixir"
    end

    test ":otp resolves to usage_rules:otp sub-rule" do
      igniter =
        project_with_deps(%{
          "deps/usage_rules/usage-rules/otp.md" => "# OTP Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:otp])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "OTP Rules"
      assert content =~ "usage_rules:otp"
    end
  end

  describe "sub-rules" do
    test "syncs a specific sub-rule with string spec" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: ["foo:ecto"])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "foo:ecto"
      assert content =~ "Foo Ecto Rules"
    end

    test "discovers all sub-rules with :all" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Main Foo",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(file: "AGENTS.md", usage_rules: :all)
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Main Foo"
      assert content =~ "Foo Ecto"
      assert content =~ "Foo Testing"
    end
  end

  describe "sub_rules option" do
    test "explicit sub_rules: :all includes main and all sub-rules" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(file: "AGENTS.md", usage_rules: [{:foo, sub_rules: :all}])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Main"
      assert content =~ "Foo Ecto"
      assert content =~ "Foo Testing"
    end

    test "sub_rules list includes main and specified sub-rules" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(file: "AGENTS.md", usage_rules: [{:foo, sub_rules: ["ecto"]}])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Main"
      assert content =~ "Foo Ecto"
      refute content =~ "Foo Testing"
    end

    test "sub_rules list errors on missing sub-rule" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Main"
      })
      |> sync(file: "AGENTS.md", usage_rules: [{:foo, sub_rules: ["nonexistent"]}])
      |> assert_has_issue(fn issue ->
        String.contains?(issue, "does not have a usage-rules/nonexistent.md file")
      end)
    end

    test "sub_rules option combines with link option" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{:foo, sub_rules: ["ecto"], link: :markdown}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "[foo usage rules](deps/foo/usage-rules.md)"
      assert content =~ "[foo:ecto usage rules](deps/foo/usage-rules/ecto.md)"
    end
  end

  describe "regex in usage_rules" do
    test "matches multiple dependencies by regex" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/ash_json_api/usage-rules.md" => "# Ash JSON API",
          "deps/req/usage-rules.md" => "# Req Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [~r/^ash/])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Ash Core"
      assert content =~ "Ash Postgres"
      assert content =~ "Ash JSON API"
      refute content =~ "Req Rules"
    end

    test "regex with link option" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/req/usage-rules.md" => "# Req Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{~r/^ash/, link: :markdown}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "[ash usage rules](deps/ash/usage-rules.md)"
      assert content =~ "[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)"
      refute content =~ "Req"
    end

    test "regex skips deps without usage-rules.md" do
      igniter =
        project_with_deps(%{
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/ash_no_rules/mix.exs" => "defmodule AshNoRules.MixProject, do: nil"
        })
        |> sync(file: "AGENTS.md", usage_rules: [~r/^ash_/])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Ash Postgres"
      refute content =~ "ash_no_rules"
    end

    test "regex and atoms can be mixed" do
      igniter =
        project_with_deps(%{
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/req/usage-rules.md" => "# Req Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [~r/^ash_/, :req])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Ash Postgres"
      assert content =~ "Req Rules"
    end

    test "regex with link: :at" do
      igniter =
        project_with_deps(%{
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{~r/^ash_/, link: :at}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "@deps/ash_postgres/usage-rules.md"
    end

    test "regex includes sub-rules by default" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash/usage-rules/ecto.md" => "# Ash Ecto",
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres"
        })
        |> sync(file: "AGENTS.md", usage_rules: [~r/^ash/])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Ash Core"
      assert content =~ "Ash Ecto"
      assert content =~ "Ash Postgres"
    end

    test "regex with sub_rules option limits sub-rules" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash/usage-rules/ecto.md" => "# Ash Ecto",
          "deps/ash/usage-rules/testing.md" => "# Ash Testing"
        })
        |> sync(file: "AGENTS.md", usage_rules: [{~r/^ash/, sub_rules: ["ecto"]}])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Ash Core"
      assert content =~ "Ash Ecto"
      refute content =~ "Ash Testing"
    end
  end

  describe "per-dep link option" do
    test "generates links with markdown style" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{:foo, link: :markdown}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "[foo usage rules](deps/foo/usage-rules.md)"
    end

    test "generates links with at-style" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{:foo, link: :at}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "@deps/foo/usage-rules.md"
    end

    test "mixes inline and linked deps" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules Content",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [:foo, {:bar, link: :markdown}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Rules Content"
      assert content =~ "[bar usage rules](deps/bar/usage-rules.md)"
    end

    test "link option works with sub-rules" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{"foo:ecto", link: :at}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "@deps/foo/usage-rules/ecto.md"
    end

    test "link option propagates to all sub-rules with :all" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{"foo:all", link: :markdown}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "[foo:ecto usage rules](deps/foo/usage-rules/ecto.md)"
      assert content =~ "[foo:testing usage rules](deps/foo/usage-rules/testing.md)"
    end
  end

  describe "updating existing AGENTS.md" do
    test "replaces usage-rules section on re-sync" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "# My Project\n\n<!-- usage-rules-start -->\n<!-- usage-rules-header -->\n# Usage Rules\n<!-- usage-rules-header-end -->\n\n<!-- old_pkg-start -->\n## old_pkg usage\nOld content\n<!-- old_pkg-end -->\n<!-- usage-rules-end -->\n\n# Other content",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "foo"
      refute content =~ "old_pkg"
      assert content =~ "Other content"
    end

    test "start marker without end marker replaces everything after start" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "# My Project\n\n<!-- usage-rules-start -->\nOld inlined content\nMore old stuff",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "# My Project"
      assert content =~ "Foo Rules"
      assert content =~ "<!-- usage-rules-end -->"
      refute content =~ "Old inlined content"
      refute content =~ "More old stuff"
    end

    test "start marker without end marker preserves prelude on re-sync" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "# My Project\n\nSome custom notes\n\n<!-- usage-rules-start -->\nOld inlined rules\nMore old rules",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [:foo]
        )

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "# My Project"
      assert content =~ "Some custom notes"
      assert content =~ "<!-- usage-rules-end -->"
      refute content =~ "Old inlined rules"
    end

    test "removes packages not in config (config is source of truth)" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "<!-- usage-rules-start -->\n<!-- usage-rules-header -->\n# Usage Rules\n<!-- usage-rules-header-end -->\n\n<!-- foo-start -->\n## foo usage\nfoo content\n<!-- foo-end -->\n<!-- bar-start -->\n## bar usage\nbar content\n<!-- bar-end -->\n<!-- usage-rules-end -->",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [:foo])

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "foo"
      refute content =~ "bar content"
    end

    test "cleans up usage-rules section when switching to skills only (start+end markers)" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "# My Project\n\nCustom notes\n\n<!-- usage-rules-start -->\nOld inline content\n<!-- usage-rules-end -->\n\nFooter",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(
          file: "AGENTS.md",
          skills: [deps: [:foo]]
        )

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "# My Project"
      assert content =~ "Custom notes"
      assert content =~ "Footer"
      refute content =~ "Old inline content"
      refute content =~ "usage-rules-start"
    end

    test "cleans up usage-rules section when no end marker (start only)" do
      igniter =
        project_with_deps(%{
          "AGENTS.md" =>
            "# My Project\n\nCustom notes\n\n<!-- usage-rules-start -->\nOld inline content\nMore old stuff",
          "deps/foo/usage-rules.md" => "# Foo Rules"
        })
        |> sync(
          file: "AGENTS.md",
          skills: [deps: [:foo]]
        )

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "# My Project"
      assert content =~ "Custom notes"
      refute content =~ "Old inline content"
      refute content =~ "More old stuff"
      refute content =~ "usage-rules-start"
    end
  end

  describe "skills.build" do
    test "builds a skill from a single package's usage rules" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage\n\nUse foo properly."
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [:foo],
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "---"
      assert content =~ "name: use-foo"
      assert content =~ "managed-by: usage-rules"
      assert content =~ "[foo](references/foo.md)"
      assert content =~ "mix usage_rules.search_docs"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo.md")
      assert ref_content =~ "Foo Usage"
    end

    test "builds a skill combining multiple packages" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nFoo guidance.",
          "deps/bar/usage-rules.md" => "# Bar Rules\n\nBar guidance."
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [:foo, :bar],
          skills: [
            location: ".claude/skills",
            build: [
              "foo-and-bar": [usage_rules: [:foo, :bar]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/foo-and-bar/SKILL.md")
        |> assert_creates(".claude/skills/foo-and-bar/references/foo.md")
        |> assert_creates(".claude/skills/foo-and-bar/references/bar.md")

      content = file_content(igniter, ".claude/skills/foo-and-bar/SKILL.md")
      assert content =~ "[foo](references/foo.md)"
      assert content =~ "[bar](references/bar.md)"
      assert content =~ "-p foo"
      assert content =~ "-p bar"
    end

    test "builds skill with custom location" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Usage"
      })
      |> sync(
        skills: [
          location: "custom/skills",
          build: [
            "use-foo": [usage_rules: [:foo]]
          ]
        ]
      )
      |> assert_creates("custom/skills/use-foo/SKILL.md")
    end

    test "skill includes sub-rules and main rules as references" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage",
          "deps/foo/usage-rules/testing.md" => "# Testing Guide"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo.md")
        |> assert_creates(".claude/skills/use-foo/references/testing.md")

      skill_content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert skill_content =~ "Additional References"
      assert skill_content =~ "[foo](references/foo.md)"
      assert skill_content =~ "[testing](references/testing.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/testing.md")
      assert ref_content =~ "Testing Guide"

      main_ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo.md")
      assert main_ref_content =~ "Foo Usage"
    end

    test "skips skills for packages not in deps" do
      project_with_deps(%{})
      |> sync(
        skills: [
          build: [
            "use-missing": [usage_rules: [:missing_pkg]]
          ]
        ]
      )
      |> assert_unchanged()
    end

    test "uses custom description when provided" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [
                usage_rules: [:foo],
                description: "Expert guidance for using Foo in production."
              ]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "Expert guidance for using Foo in production."
    end

    test "uses YAML block scalar for multiline description" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [
                usage_rules: [:foo],
                description: """
                Use this skill working with Foo.
                Always consult this when making changes.
                """
              ]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "description: >-\n"
      assert content =~ "  Use this skill working with Foo."
      assert content =~ "  Always consult this when making changes."
    end

    test "preserves custom content in skill on re-sync" do
      existing_skill =
        "---\nname: use-foo\ndescription: \"old\"\nmetadata:\n  managed-by: usage-rules\n---\n\nMy custom instructions\n\n<!-- usage-rules-skill-start -->\nOld body\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage\n\nUpdated content.",
          ".claude/skills/use-foo/SKILL.md" => existing_skill
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "My custom instructions"
      assert content =~ "[foo](references/foo.md)"
      assert content =~ "<!-- usage-rules-skill-start -->"
      refute content =~ "Old body"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo.md")
      assert ref_content =~ "Updated content."
    end

    test "skill includes managed section markers" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "<!-- usage-rules-skill-start -->"
      assert content =~ "<!-- usage-rules-skill-end -->"
    end

    test "builds multiple skills" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules",
        "deps/bar/usage-rules.md" => "# Bar Rules"
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          build: [
            "use-foo": [usage_rules: [:foo]],
            "use-bar": [usage_rules: [:bar]]
          ]
        ]
      )
      |> assert_creates(".claude/skills/use-foo/SKILL.md")
      |> assert_creates(".claude/skills/use-bar/SKILL.md")
    end

    test "build supports regex in usage_rules to match multiple deps" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/ash_json_api/usage-rules.md" => "# Ash JSON API",
          "deps/req/usage-rules.md" => "# Req"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-ash": [usage_rules: [:ash, ~r/^ash_/]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-ash/SKILL.md")
        |> assert_creates(".claude/skills/use-ash/references/ash.md")
        |> assert_creates(".claude/skills/use-ash/references/ash_postgres.md")
        |> assert_creates(".claude/skills/use-ash/references/ash_json_api.md")

      content = file_content(igniter, ".claude/skills/use-ash/SKILL.md")
      assert content =~ "[ash](references/ash.md)"
      assert content =~ "[ash_postgres](references/ash_postgres.md)"
      assert content =~ "[ash_json_api](references/ash_json_api.md)"
      refute content =~ "Req"
    end

    test "removes stale managed skills no longer in build list" do
      stale_skill_md =
        "---\nname: use-old\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\nOld skill.\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "skills/use-old/SKILL.md" => stale_skill_md
        })
        |> sync(
          skills: [
            location: "skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates("skills/use-foo/SKILL.md")

      # The stale skill should have been removed
      assert "skills/use-old/SKILL.md" not in Map.keys(igniter.rewrite.sources)
    end

    test "preserves stale skill with custom content" do
      stale_skill_md =
        "---\nname: use-old\nmetadata:\n  managed-by: usage-rules\n---\n\nMy custom notes\n\n<!-- usage-rules-skill-start -->\nOld skill.\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "skills/use-old/SKILL.md" => stale_skill_md
        })
        |> sync(
          skills: [
            location: "skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates("skills/use-foo/SKILL.md")

      # The stale skill should be kept with custom content preserved
      assert Map.has_key?(igniter.rewrite.sources, "skills/use-old/SKILL.md")
      content = file_content(igniter, "skills/use-old/SKILL.md")
      assert content =~ "My custom notes"
      refute content =~ "usage-rules-skill-start"
      refute content =~ "managed-by: usage-rules"
    end

    test "does not remove non-managed skills" do
      unmanaged_skill_md = "---\nname: custom-skill\n---\nCustom skill."

      managed_skill_md =
        "---\nname: use-old\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\nOld.\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "skills/custom-skill/SKILL.md" => unmanaged_skill_md,
          "skills/use-old/SKILL.md" => managed_skill_md
        })
        |> sync(
          skills: [
            location: "skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates("skills/use-foo/SKILL.md")

      # Managed stale skill removed, non-managed skill left alone
      refute Map.has_key?(igniter.rewrite.sources, "skills/use-old/SKILL.md")
      assert Map.has_key?(igniter.rewrite.sources, "skills/custom-skill/SKILL.md")
    end
  end

  describe "skills.deps (auto-build shorthand)" do
    test "auto-builds a use-<pkg> skill from a single package" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Usage\n\nUse foo properly."
        })
        |> sync(skills: [location: ".claude/skills", deps: [:foo]])
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "name: use-foo"
      assert content =~ "managed-by: usage-rules"
      assert content =~ "[foo](references/foo.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo.md")
      assert ref_content =~ "Foo Usage"
    end

    test "auto-builds skills for multiple packages" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules",
        "deps/bar/usage-rules.md" => "# Bar Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [:foo, :bar]])
      |> assert_creates(".claude/skills/use-foo/SKILL.md")
      |> assert_creates(".claude/skills/use-bar/SKILL.md")
    end

    test "deps and build can be combined" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            deps: [:foo],
            build: [
              "foo-and-bar": [usage_rules: [:foo, :bar]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/foo-and-bar/SKILL.md")

      combo_content = file_content(igniter, ".claude/skills/foo-and-bar/SKILL.md")
      assert combo_content =~ "[foo](references/foo.md)"
      assert combo_content =~ "[bar](references/bar.md)"
    end

    test "supports regex to match multiple deps" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
        "deps/ash_json_api/usage-rules.md" => "# Ash JSON API Rules",
        "deps/req/usage-rules.md" => "# Req Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/]])
      |> assert_creates(".claude/skills/use-ash_postgres/SKILL.md")
      |> assert_creates(".claude/skills/use-ash_json_api/SKILL.md")
    end

    test "regex skips deps without usage-rules.md" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
        "deps/ash_no_rules/mix.exs" => "defmodule AshNoRules.MixProject, do: nil"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/]])
      |> assert_creates(".claude/skills/use-ash_postgres/SKILL.md")
    end

    test "regex and atoms can be mixed" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
        "deps/req/usage-rules.md" => "# Req Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/, :req]])
      |> assert_creates(".claude/skills/use-ash_postgres/SKILL.md")
      |> assert_creates(".claude/skills/use-req/SKILL.md")
    end

    test "duplicates from regex and atom are deduped" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/, :ash_postgres]])
      |> assert_creates(".claude/skills/use-ash_postgres/SKILL.md")
    end
  end

  describe "combined usage_rules and skills" do
    test "syncs AGENTS.md and builds skills together" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [:foo, :bar],
          skills: [
            location: ".claude/skills",
            deps: [:foo],
            build: [
              "use-bar": [usage_rules: [:bar]]
            ]
          ]
        )
        |> assert_creates("AGENTS.md")
        |> assert_creates(".claude/skills/use-bar/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      agents_content = file_content(igniter, "AGENTS.md")
      assert agents_content =~ "foo"
      assert agents_content =~ "bar"

      skill_content = file_content(igniter, ".claude/skills/use-bar/SKILL.md")
      assert skill_content =~ "[bar](references/bar.md)"
    end
  end

  describe "no file config (skills only)" do
    test "generates skills without AGENTS.md when file is not configured" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [:foo]])
      |> assert_creates(".claude/skills/use-foo/SKILL.md")
    end
  end

  describe "deprecated {:dep, :reference} format" do
    test "build with {:dep, :reference} still works but all packages are references" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nFoo guidance.",
          "deps/bar/usage-rules.md" => "# Bar Rules\n\nBar guidance."
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "my-skill": [usage_rules: [:foo, {:bar, :reference}]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/my-skill/SKILL.md")
        |> assert_creates(".claude/skills/my-skill/references/foo.md")
        |> assert_creates(".claude/skills/my-skill/references/bar.md")

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      # Both foo and bar should be reference links
      assert skill_content =~ "[foo](references/foo.md)"
      assert skill_content =~ "[bar](references/bar.md)"

      foo_ref = file_content(igniter, ".claude/skills/my-skill/references/foo.md")
      assert foo_ref =~ "Foo Rules"

      bar_ref = file_content(igniter, ".claude/skills/my-skill/references/bar.md")
      assert bar_ref =~ "Bar Rules"
    end

    test "build with {~r/.../, :reference} still works but all packages are references" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
          "deps/ash_json_api/usage-rules.md" => "# Ash JSON API"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "ash-expert": [usage_rules: [:ash, {~r/^ash_/, :reference}]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/ash-expert/SKILL.md")
        |> assert_creates(".claude/skills/ash-expert/references/ash.md")
        |> assert_creates(".claude/skills/ash-expert/references/ash_postgres.md")
        |> assert_creates(".claude/skills/ash-expert/references/ash_json_api.md")

      skill_content = file_content(igniter, ".claude/skills/ash-expert/SKILL.md")
      assert skill_content =~ "[ash](references/ash.md)"
      assert skill_content =~ "[ash_postgres](references/ash_postgres.md)"
      assert skill_content =~ "[ash_json_api](references/ash_json_api.md)"
    end

    test "deps config with {:dep, :reference} still works" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nFoo content."
        })
        |> sync(skills: [location: ".claude/skills", deps: [{:foo, :reference}]])
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo.md")

      skill_content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert skill_content =~ "[foo](references/foo.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo.md")
      assert ref_content =~ "Foo Rules"
    end

    test "deps config with {~r/.../, :reference} still works" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
        "deps/ash_json_api/usage-rules.md" => "# Ash JSON API Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [{~r/^ash_/, :reference}]])
      |> assert_creates(".claude/skills/use-ash_postgres/SKILL.md")
      |> assert_creates(".claude/skills/use-ash_postgres/references/ash_postgres.md")
      |> assert_creates(".claude/skills/use-ash_json_api/SKILL.md")
      |> assert_creates(".claude/skills/use-ash_json_api/references/ash_json_api.md")
    end

    test "all packages appear in search docs section" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "my-skill": [usage_rules: [:foo, :bar]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/my-skill/SKILL.md")

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert skill_content =~ "-p foo"
      assert skill_content =~ "-p bar"
    end

    test "main rules and sub-rules both appear in Additional References" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "my-skill": [usage_rules: [:foo, :bar]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/my-skill/SKILL.md")
        |> assert_creates(".claude/skills/my-skill/references/foo.md")
        |> assert_creates(".claude/skills/my-skill/references/testing.md")
        |> assert_creates(".claude/skills/my-skill/references/bar.md")

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert skill_content =~ "Additional References"
      assert skill_content =~ "[foo](references/foo.md)"
      assert skill_content =~ "[testing](references/testing.md)"
      assert skill_content =~ "[bar](references/bar.md)"
    end
  end
end
