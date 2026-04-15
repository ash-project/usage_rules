# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.SyncTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
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

  defp capture_stderr_result(fun) do
    parent = self()

    output =
      capture_io(:stderr, fn ->
        send(parent, {:captured_result, fun.()})
      end)

    result =
      receive do
        {:captured_result, result} -> result
      end

    {output, result}
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

    test "syncs with {:all, link: :markdown} generates markdown links for all packages" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: {:all, link: :markdown})
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "[bar usage rules](deps/bar/usage-rules.md)"
      assert content =~ "[foo usage rules](deps/foo/usage-rules.md)"
    end

    test "syncs with {:all, link: :at} generates @ links for all packages" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/bar/usage-rules.md" => "# Bar Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: {:all, link: :at})
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "@deps/bar/usage-rules.md"
      assert content =~ "@deps/foo/usage-rules.md"
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

    test "main: false suppresses the main usage-rules.md" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto",
          "deps/foo/usage-rules/testing.md" => "# Foo Testing"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [{:foo, sub_rules: :all, main: false}]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      refute content =~ "Foo Main"
      assert content =~ "Foo Ecto"
      assert content =~ "Foo Testing"
    end

    test "main: false with link option for sub-rules only" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Main",
          "deps/foo/usage-rules/ecto.md" => "# Foo Ecto"
        })
        |> sync(
          file: "AGENTS.md",
          usage_rules: [
            {:foo, sub_rules: []},
            {:foo, sub_rules: :all, main: false, link: :markdown}
          ]
        )
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")
      assert content =~ "Foo Main"
      refute content =~ "[foo usage rules]"
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

    test "regex produces sections in stable sorted order" do
      igniter =
        project_with_deps(%{
          "deps/zeta/usage-rules.md" => "# Zeta Rules",
          "deps/alpha/usage-rules.md" => "# Alpha Rules",
          "deps/mango/usage-rules.md" => "# Mango Rules"
        })
        |> sync(file: "AGENTS.md", usage_rules: [~r/./])
        |> assert_creates("AGENTS.md")

      content = file_content(igniter, "AGENTS.md")

      alpha_pos = :binary.match(content, "## alpha usage") |> elem(0)
      mango_pos = :binary.match(content, "## mango usage") |> elem(0)
      zeta_pos = :binary.match(content, "## zeta usage") |> elem(0)

      assert alpha_pos < mango_pos
      assert mango_pos < zeta_pos
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
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "---"
      assert content =~ "name: use-foo"
      assert content =~ "managed-by: usage-rules"
      assert content =~ "### foo"
      assert content =~ "[foo](references/foo/foo.md)"
      assert content =~ "mix usage_rules.search_docs"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")
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
        |> assert_creates(".claude/skills/foo-and-bar/references/foo/foo.md")
        |> assert_creates(".claude/skills/foo-and-bar/references/bar/bar.md")

      content = file_content(igniter, ".claude/skills/foo-and-bar/SKILL.md")
      assert content =~ "### foo"
      assert content =~ "### bar"
      assert content =~ "[foo](references/foo/foo.md)"
      assert content =~ "[bar](references/bar/bar.md)"
      assert content =~ "-p foo"
      assert content =~ "-p bar"

      assert :binary.match(content, "### foo") < :binary.match(content, "### bar")
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
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")
        |> assert_creates(".claude/skills/use-foo/references/foo/testing.md")

      skill_content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert skill_content =~ "Additional References"
      assert skill_content =~ "### foo"
      assert skill_content =~ "[foo](references/foo/foo.md)"
      assert skill_content =~ "[testing](references/foo/testing.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/testing.md")
      assert ref_content =~ "Testing Guide"

      main_ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")
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
      assert content =~ "[foo](references/foo/foo.md)"
      assert content =~ "<!-- usage-rules-skill-start -->"
      refute content =~ "Old body"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")
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
        |> assert_creates(".claude/skills/use-ash/references/ash/ash.md")
        |> assert_creates(".claude/skills/use-ash/references/ash_postgres/ash_postgres.md")
        |> assert_creates(".claude/skills/use-ash/references/ash_json_api/ash_json_api.md")

      content = file_content(igniter, ".claude/skills/use-ash/SKILL.md")
      assert content =~ "[ash](references/ash/ash.md)"
      assert content =~ "[ash_postgres](references/ash_postgres/ash_postgres.md)"
      assert content =~ "[ash_json_api](references/ash_json_api/ash_json_api.md)"
      refute content =~ "Req"
    end

    test "regex build skips reference links for deps without usage rules but includes them in search docs" do
      igniter =
        project_with_deps(%{
          "deps/phoenix/usage-rules/ecto.md" => "# Phoenix Ecto",
          "deps/phoenix/usage-rules/liveview.md" => "# Phoenix LiveView",
          "deps/phoenix_ecto/mix.exs" => "defmodule PhoenixEcto.MixProject, do: nil",
          "deps/phoenix_html/mix.exs" => "defmodule PhoenixHTML.MixProject, do: nil"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "phoenix-framework": [usage_rules: [:phoenix, ~r/^phoenix_/]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/phoenix-framework/SKILL.md")
        |> assert_creates(".claude/skills/phoenix-framework/references/phoenix/ecto.md")
        |> assert_creates(".claude/skills/phoenix-framework/references/phoenix/liveview.md")

      content = file_content(igniter, ".claude/skills/phoenix-framework/SKILL.md")

      # Sub-rule references are included under the phoenix package heading
      assert content =~ "### phoenix"
      assert content =~ "[ecto](references/phoenix/ecto.md)"
      assert content =~ "[liveview](references/phoenix/liveview.md)"

      # Deps without usage rules should NOT have reference links or package dirs
      refute content =~ "references/phoenix_ecto/"
      refute content =~ "references/phoenix_html/"

      # Package with only sub-rules (no main usage-rules.md) should NOT have a main reference link
      refute content =~ "[phoenix](references/phoenix/phoenix.md)"

      # But search docs should include ALL matched deps (they have hexdocs regardless)
      assert content =~ "-p phoenix_ecto"
      assert content =~ "-p phoenix_html"
      assert content =~ "-p phoenix"
    end

    test "deps with main usage-rules.md get reference links, sub-rules-only deps do not" do
      igniter =
        project_with_deps(%{
          # ash has a main usage-rules.md
          "deps/ash/usage-rules.md" => "# Ash Framework",
          # ash_postgres has only sub-rules, no main usage-rules.md
          "deps/ash_postgres/usage-rules/migrations.md" => "# Migrations",
          # ash_oban has no usage rules at all
          "deps/ash_oban/mix.exs" => "defmodule AshOban.MixProject, do: nil"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "ash-framework": [usage_rules: [:ash, ~r/^ash_/]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/ash-framework/SKILL.md")
        |> assert_creates(".claude/skills/ash-framework/references/ash/ash.md")
        |> assert_creates(".claude/skills/ash-framework/references/ash_postgres/migrations.md")

      content = file_content(igniter, ".claude/skills/ash-framework/SKILL.md")

      # ash has main usage-rules.md → gets its own H3 + main reference link
      assert content =~ "### ash"
      assert content =~ "[ash](references/ash/ash.md)"

      # ash_postgres has sub-rules → H3 present with sub-rule link, but no main link
      assert content =~ "### ash_postgres"
      assert content =~ "[migrations](references/ash_postgres/migrations.md)"
      refute content =~ "[ash_postgres](references/ash_postgres/ash_postgres.md)"

      # ash_oban has no usage rules → no H3, no reference dir
      refute content =~ "### ash_oban"
      refute content =~ "references/ash_oban/"

      # Search docs include all matched deps
      assert content =~ "-p ash"
      assert content =~ "-p ash_postgres"
      assert content =~ "-p ash_oban"
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

    test "no duplicate references when sub-rule name matches package name" do
      igniter =
        project_with_deps(%{
          "deps/phoenix/usage-rules/phoenix.md" => "# Phoenix Rules",
          "deps/phoenix/usage-rules/liveview.md" => "# LiveView Rules"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "my-skill": [usage_rules: [:phoenix]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/my-skill/SKILL.md")
        |> assert_creates(".claude/skills/my-skill/references/phoenix/phoenix.md")
        |> assert_creates(".claude/skills/my-skill/references/phoenix/liveview.md")

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")

      assert skill_content =~ "Additional References"
      assert skill_content =~ "### phoenix"
      assert skill_content =~ "[liveview](references/phoenix/liveview.md)"

      # phoenix sub-rule appears exactly once (package has no main usage-rules.md,
      # so there's no package-level [phoenix] link to collide with the sub-rule)
      assert [_] =
               Regex.scan(
                 ~r"\[phoenix\]\(references/phoenix/phoenix\.md\)",
                 skill_content
               )
    end

    test "cross-package sub-rule name collision keeps both references" do
      igniter =
        project_with_deps(%{
          "deps/ash/usage-rules.md" => "# Ash Core",
          "deps/ash/usage-rules/multitenancy.md" => "# Ash Multitenancy\n\nAsh's take.",
          "deps/ash_oban/usage-rules.md" => "# Ash Oban",
          "deps/ash_oban/usage-rules/multitenancy.md" => "# Oban Multitenancy\n\nOban's take."
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "ash-framework": [usage_rules: [:ash, :ash_oban]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/ash-framework/SKILL.md")
        |> assert_creates(".claude/skills/ash-framework/references/ash/multitenancy.md")
        |> assert_creates(".claude/skills/ash-framework/references/ash_oban/multitenancy.md")

      # Both files exist with distinct content — the silent overwrite is gone
      ash_multi =
        file_content(igniter, ".claude/skills/ash-framework/references/ash/multitenancy.md")

      oban_multi =
        file_content(igniter, ".claude/skills/ash-framework/references/ash_oban/multitenancy.md")

      assert ash_multi =~ "Ash's take."
      assert oban_multi =~ "Oban's take."
      refute ash_multi == oban_multi

      content = file_content(igniter, ".claude/skills/ash-framework/SKILL.md")
      assert content =~ "### ash"
      assert content =~ "### ash_oban"
      assert content =~ "[multitenancy](references/ash/multitenancy.md)"
      assert content =~ "[multitenancy](references/ash_oban/multitenancy.md)"
    end

    test "package with only sub-rules still gets an H3 heading" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/testing.md" => "# Testing"
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
        |> assert_creates(".claude/skills/use-foo/references/foo/testing.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "### foo"
      assert content =~ "[testing](references/foo/testing.md)"
      # No main rule link because deps/foo/usage-rules.md does not exist
      refute content =~ "[foo](references/foo/foo.md)"
    end

    test "H3 headings appear in the config order of usage_rules" do
      igniter =
        project_with_deps(%{
          "deps/zebra/usage-rules.md" => "# Zebra",
          "deps/alpha/usage-rules.md" => "# Alpha",
          "deps/middle/usage-rules.md" => "# Middle"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              ordered: [usage_rules: [:zebra, :alpha, :middle]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/ordered/SKILL.md")

      content = file_content(igniter, ".claude/skills/ordered/SKILL.md")

      # Headings appear in exactly the order declared in the config.
      {zebra_idx, _} = :binary.match(content, "### zebra")
      {alpha_idx, _} = :binary.match(content, "### alpha")
      {middle_idx, _} = :binary.match(content, "### middle")

      assert zebra_idx < alpha_idx
      assert alpha_idx < middle_idx
    end

    test "stale flat-layout reference files are cleaned up on re-sync" do
      # Pre-seed an old-layout reference file as if an earlier version of
      # usage_rules had written it. The sync should remove it and write the
      # new per-package layout instead.
      stale_skill_md =
        "---\nname: use-foo\ndescription: \"Foo skill\"\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\n## Additional References\n\n- [foo](references/foo.md)\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          ".claude/skills/use-foo/SKILL.md" => stale_skill_md,
          ".claude/skills/use-foo/references/foo.md" => "# Old flat-layout content"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [usage_rules: [:foo]]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")

      # Old flat-layout file removed
      refute Map.has_key?(
               igniter.rewrite.sources,
               ".claude/skills/use-foo/references/foo.md"
             )

      # New nested content written with fresh package content
      ref =
        file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")

      assert ref =~ "Foo Rules"

      # SKILL.md points at the new location
      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "[foo](references/foo/foo.md)"
      refute content =~ "[foo](references/foo.md)"
    end

    test "per-package reference directory is removed when package leaves the skill" do
      # First sync: build a skill containing both foo and bar
      config_both = [
        skills: [
          location: ".claude/skills",
          build: [
            combo: [usage_rules: [:foo, :bar]]
          ]
        ]
      ]

      config_foo_only = [
        skills: [
          location: ".claude/skills",
          build: [
            combo: [usage_rules: [:foo]]
          ]
        ]
      ]

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo",
          "deps/bar/usage-rules.md" => "# Bar"
        })
        |> sync(config_both)
        |> assert_creates(".claude/skills/combo/references/foo/foo.md")
        |> assert_creates(".claude/skills/combo/references/bar/bar.md")
        |> apply_igniter!()

      # Second sync drops bar from the build
      igniter =
        igniter
        |> sync(config_foo_only)

      # bar's reference file is gone; foo's remains
      refute Map.has_key?(
               igniter.rewrite.sources,
               ".claude/skills/combo/references/bar/bar.md"
             )

      assert Map.has_key?(
               igniter.rewrite.sources,
               ".claude/skills/combo/references/foo/foo.md"
             )

      content = file_content(igniter, ".claude/skills/combo/SKILL.md")
      refute content =~ "### bar"
      refute content =~ "references/bar/"
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
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "name: use-foo"
      assert content =~ "managed-by: usage-rules"
      assert content =~ "[foo](references/foo/foo.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")
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
      assert combo_content =~ "[foo](references/foo/foo.md)"
      assert combo_content =~ "[bar](references/bar/bar.md)"
    end

    test "supports regex to match multiple deps" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
        "deps/ash_json_api/usage-rules.md" => "# Ash JSON API Rules",
        "deps/req/usage-rules.md" => "# Req Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/]])
      |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")
      |> assert_creates(".claude/skills/use-ash-json-api/SKILL.md")
    end

    test "regex skips deps without usage-rules.md" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
        "deps/ash_no_rules/mix.exs" => "defmodule AshNoRules.MixProject, do: nil"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/]])
      |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")
    end

    test "regex and atoms can be mixed" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres",
        "deps/req/usage-rules.md" => "# Req Rules"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/, :req]])
      |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")
      |> assert_creates(".claude/skills/use-req/SKILL.md")
    end

    test "duplicates from regex and atom are deduped" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules.md" => "# Ash Postgres"
      })
      |> sync(skills: [location: ".claude/skills", deps: [~r/^ash_/, :ash_postgres]])
      |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")
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
      assert skill_content =~ "[bar](references/bar/bar.md)"
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
      {output, igniter} =
        capture_stderr_result(fn ->
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
          |> assert_creates(".claude/skills/my-skill/references/foo/foo.md")
          |> assert_creates(".claude/skills/my-skill/references/bar/bar.md")
        end)

      assert output =~ "deprecated in usage_rules skill config"

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      # Both foo and bar should be reference links under per-package dirs
      assert skill_content =~ "[foo](references/foo/foo.md)"
      assert skill_content =~ "[bar](references/bar/bar.md)"

      foo_ref = file_content(igniter, ".claude/skills/my-skill/references/foo/foo.md")
      assert foo_ref =~ "Foo Rules"

      bar_ref = file_content(igniter, ".claude/skills/my-skill/references/bar/bar.md")
      assert bar_ref =~ "Bar Rules"
    end

    test "build with {~r/.../, :reference} still works but all packages are references" do
      {output, igniter} =
        capture_stderr_result(fn ->
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
          |> assert_creates(".claude/skills/ash-expert/references/ash/ash.md")
          |> assert_creates(".claude/skills/ash-expert/references/ash_postgres/ash_postgres.md")
          |> assert_creates(".claude/skills/ash-expert/references/ash_json_api/ash_json_api.md")
        end)

      assert output =~ "deprecated in usage_rules skill config"

      skill_content = file_content(igniter, ".claude/skills/ash-expert/SKILL.md")
      assert skill_content =~ "[ash](references/ash/ash.md)"
      assert skill_content =~ "[ash_postgres](references/ash_postgres/ash_postgres.md)"
      assert skill_content =~ "[ash_json_api](references/ash_json_api/ash_json_api.md)"
    end

    test "deps config with {:dep, :reference} still works" do
      {output, igniter} =
        capture_stderr_result(fn ->
          project_with_deps(%{
            "deps/foo/usage-rules.md" => "# Foo Rules\n\nFoo content."
          })
          |> sync(skills: [location: ".claude/skills", deps: [{:foo, :reference}]])
          |> assert_creates(".claude/skills/use-foo/SKILL.md")
          |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")
        end)

      assert output =~ "deprecated in usage_rules skill config"

      skill_content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert skill_content =~ "[foo](references/foo/foo.md)"

      ref_content = file_content(igniter, ".claude/skills/use-foo/references/foo/foo.md")
      assert ref_content =~ "Foo Rules"
    end

    test "deps config with {~r/.../, :reference} still works" do
      {output, _igniter} =
        capture_stderr_result(fn ->
          project_with_deps(%{
            "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
            "deps/ash_json_api/usage-rules.md" => "# Ash JSON API Rules"
          })
          |> sync(skills: [location: ".claude/skills", deps: [{~r/^ash_/, :reference}]])
          |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")
          |> assert_creates(
            ".claude/skills/use-ash-postgres/references/ash_postgres/ash_postgres.md"
          )
          |> assert_creates(".claude/skills/use-ash-json-api/SKILL.md")
          |> assert_creates(
            ".claude/skills/use-ash-json-api/references/ash_json_api/ash_json_api.md"
          )
        end)

      assert output =~ "deprecated in usage_rules skill config"
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
        |> assert_creates(".claude/skills/my-skill/references/foo/foo.md")
        |> assert_creates(".claude/skills/my-skill/references/foo/testing.md")
        |> assert_creates(".claude/skills/my-skill/references/bar/bar.md")

      skill_content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert skill_content =~ "Additional References"
      assert skill_content =~ "### foo"
      assert skill_content =~ "### bar"
      assert skill_content =~ "[foo](references/foo/foo.md)"
      assert skill_content =~ "[testing](references/foo/testing.md)"
      assert skill_content =~ "[bar](references/bar/bar.md)"
    end
  end

  describe "skills.package_skills (package-provided skills)" do
    test "copies a pre-built skill from a package" do
      skill_content = """
      ---
      name: my-skill
      description: "Use this when working with Foo."
      ---

      ## Overview

      Foo is great.
      """

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/skills/my-skill/SKILL.md" => skill_content
        })
        |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])
        |> assert_creates(".claude/skills/my-skill/SKILL.md")

      content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert content =~ "name: my-skill"
      assert content =~ "managed-by: usage-rules"
      assert content =~ "Foo is great."
      assert content =~ "<!-- usage-rules-skill-start -->"
      assert content =~ "<!-- usage-rules-skill-end -->"
    end

    test "injects managed-by into existing metadata block" do
      skill_content = """
      ---
      name: my-skill
      description: "Use when working with Foo."
      metadata:
        author: foo-team
      ---

      Content here.
      """

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/skills/my-skill/SKILL.md" => skill_content
        })
        |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])

      content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert content =~ "managed-by: usage-rules"
      assert content =~ "author: foo-team"
    end

    test "injects metadata section when no metadata in frontmatter" do
      skill_content = """
      ---
      name: my-skill
      description: "A skill."
      ---

      Content.
      """

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/skills/my-skill/SKILL.md" => skill_content
        })
        |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])

      content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert content =~ "metadata:\n  managed-by: usage-rules"
    end

    test "handles skill with no frontmatter" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/skills/my-skill/SKILL.md" => "Just content, no frontmatter."
        })
        |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])

      content = file_content(igniter, ".claude/skills/my-skill/SKILL.md")
      assert content =~ "managed-by: usage-rules"
      assert content =~ "Just content, no frontmatter."
    end

    test "copies companion reference files" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules/skills/my-skill/SKILL.md" => "---\nname: my-skill\n---\nBody.",
          "deps/foo/usage-rules/skills/my-skill/references/guide.md" => "# Guide"
        })
        |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])
        |> assert_creates(".claude/skills/my-skill/SKILL.md")
        |> assert_creates(".claude/skills/my-skill/references/guide.md")

      ref_content = file_content(igniter, ".claude/skills/my-skill/references/guide.md")
      assert ref_content =~ "# Guide"
    end

    test "supports regex to match multiple packages" do
      project_with_deps(%{
        "deps/ash_postgres/usage-rules/skills/ash-postgres/SKILL.md" =>
          "---\nname: ash-postgres\n---\nContent.",
        "deps/ash_json_api/usage-rules/skills/ash-json-api/SKILL.md" =>
          "---\nname: ash-json-api\n---\nContent.",
        "deps/req/usage-rules/skills/req/SKILL.md" => "---\nname: req\n---\nContent."
      })
      |> sync(skills: [location: ".claude/skills", package_skills: [~r/^ash_/]])
      |> assert_creates(".claude/skills/ash-postgres/SKILL.md")
      |> assert_creates(".claude/skills/ash-json-api/SKILL.md")
    end

    test "multiple packages can each provide multiple skills" do
      project_with_deps(%{
        "deps/foo/usage-rules/skills/skill-a/SKILL.md" => "---\nname: skill-a\n---\nA.",
        "deps/foo/usage-rules/skills/skill-b/SKILL.md" => "---\nname: skill-b\n---\nB.",
        "deps/bar/usage-rules/skills/skill-c/SKILL.md" => "---\nname: skill-c\n---\nC."
      })
      |> sync(skills: [location: ".claude/skills", package_skills: [:foo, :bar]])
      |> assert_creates(".claude/skills/skill-a/SKILL.md")
      |> assert_creates(".claude/skills/skill-b/SKILL.md")
      |> assert_creates(".claude/skills/skill-c/SKILL.md")
    end

    test "stale package skills are removed on re-sync" do
      stale_skill_md =
        "---\nname: my-skill\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\nContent.\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          ".claude/skills/my-skill/SKILL.md" => stale_skill_md
        })
        |> sync(skills: [location: ".claude/skills", deps: [:foo]])

      # The stale package skill should have been removed
      assert ".claude/skills/my-skill/SKILL.md" not in Map.keys(igniter.rewrite.sources)
    end

    test "package_skills and build can be combined" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo Rules",
        "deps/bar/usage-rules/skills/bar-skill/SKILL.md" =>
          "---\nname: bar-skill\n---\nBar content."
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          package_skills: [:bar],
          build: [
            "foo-built": [usage_rules: [:foo]]
          ]
        ]
      )
      |> assert_creates(".claude/skills/bar-skill/SKILL.md")
      |> assert_creates(".claude/skills/foo-built/SKILL.md")
    end
  end

  describe "idempotency (--check)" do
    # Rewrite.Source.write/2 calls eof_newline/1 before File.write/2
    # (see rewrite/lib/rewrite/source.ex line ~297 and ~970):
    #
    #   defp write(%Source{path: path, content: content}, ...) do
    #     file_write(path, eof_newline(content))
    #   end
    #   defp eof_newline(string), do: String.trim_trailing(string) <> "\n"
    #
    # In test mode, simulate_write stores raw content without this
    # normalization, so tests don't reproduce the trailing-newline mismatch
    # that causes --check failures in real usage.  This helper applies the
    # same eof_newline transform to simulate a real disk round-trip.
    defp simulate_disk_roundtrip(igniter) do
      test_files =
        Enum.reduce(igniter.assigns[:test_files], igniter.assigns[:test_files], fn
          {"deps/" <> _, _content}, acc ->
            acc

          {_path, ""}, acc ->
            acc

          {path, content}, acc ->
            Map.put(acc, path, String.trim_trailing(content) <> "\n")
        end)

      igniter
      |> Map.put(:rewrite, Rewrite.new())
      |> Map.put(:assigns, %{
        test_mode?: true,
        test_files: test_files,
        igniter_exs: igniter.assigns[:igniter_exs]
      })
      |> Igniter.include_glob("**/*.*")
    end

    test "second sync reports no changes for skills.build" do
      config = [
        skills: [
          location: ".claude/skills",
          build: [
            "use-foo": [
              description: "Foo skill",
              usage_rules: [:foo, :bar]
            ]
          ]
        ]
      ]

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nUse foo wisely.",
          "deps/bar/usage-rules.md" => "# Bar Rules\n\nUse bar wisely."
        })
        |> sync(config)
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")
        |> assert_creates(".claude/skills/use-foo/references/bar/bar.md")
        |> apply_igniter!()
        |> simulate_disk_roundtrip()

      igniter
      |> sync(config)
      |> assert_unchanged()
    end

    test "second sync reports no changes for skills.deps" do
      config = [
        skills: [
          location: ".claude/skills",
          deps: [:foo]
        ]
      ]

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nUse foo wisely."
        })
        |> sync(config)
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> apply_igniter!()
        |> simulate_disk_roundtrip()

      igniter
      |> sync(config)
      |> assert_unchanged()
    end

    test "second sync reports no changes for AGENTS.md" do
      config = [
        file: "AGENTS.md",
        usage_rules: [:foo]
      ]

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nUse foo wisely."
        })
        |> sync(config)
        |> assert_creates("AGENTS.md")
        |> apply_igniter!()
        |> simulate_disk_roundtrip()

      igniter
      |> sync(config)
      |> assert_unchanged()
    end

    test "second sync reports no changes with sub-rules" do
      config = [
        skills: [
          location: ".claude/skills",
          build: [
            "use-foo": [usage_rules: [:foo]]
          ]
        ]
      ]

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules",
          "deps/foo/usage-rules/testing.md" => "# Testing Guide"
        })
        |> sync(config)
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")
        |> assert_creates(".claude/skills/use-foo/references/foo/testing.md")
        |> apply_igniter!()
        |> simulate_disk_roundtrip()

      igniter
      |> sync(config)
      |> assert_unchanged()
    end

    test "second sync reports no changes with custom content in SKILL.md" do
      config = [
        skills: [
          location: ".claude/skills",
          build: [
            "use-foo": [
              description: "Foo skill",
              usage_rules: [:foo]
            ]
          ]
        ]
      ]

      # First sync creates the skill
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo Rules\n\nUse foo wisely."
        })
        |> sync(config)
        |> assert_creates(".claude/skills/use-foo/SKILL.md")
        |> assert_creates(".claude/skills/use-foo/references/foo/foo.md")
        |> apply_igniter!()

      # Inject custom content between frontmatter and managed section
      skill_content = igniter.assigns[:test_files][".claude/skills/use-foo/SKILL.md"]

      [frontmatter, managed] =
        String.split(skill_content, "\n\n<!-- usage-rules-skill-start -->", parts: 2)

      custom_skill =
        frontmatter <>
          "\n\nMy custom instructions go here.\n\n<!-- usage-rules-skill-start -->" <>
          managed

      test_files =
        Map.put(igniter.assigns[:test_files], ".claude/skills/use-foo/SKILL.md", custom_skill)

      igniter = put_in(igniter.assigns[:test_files], test_files)

      igniter =
        igniter
        |> simulate_disk_roundtrip()

      # Second sync should preserve custom content and report no changes
      igniter
      |> sync(config)
      |> assert_unchanged()
    end
  end

  describe "agentskills.io spec compliance" do
    test "skill name uses hyphens instead of underscores (auto-built from deps)" do
      igniter =
        project_with_deps(%{
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres"
        })
        |> sync(skills: [location: ".claude/skills", deps: [:ash_postgres]])
        |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-ash-postgres/SKILL.md")
      assert content =~ "name: use-ash-postgres"
    end

    test "removes old skill with underscore name when normalized name is generated" do
      old_skill_md =
        "---\nname: use-ash_postgres\ndescription: \"Old.\"\nmetadata:\n  managed-by: usage-rules\n---\n\n<!-- usage-rules-skill-start -->\nOld content.\n<!-- usage-rules-skill-end -->"

      igniter =
        project_with_deps(%{
          "deps/ash_postgres/usage-rules.md" => "# Ash Postgres Rules",
          ".claude/skills/use-ash_postgres/SKILL.md" => old_skill_md
        })
        |> Igniter.include_or_create_file(
          ".claude/skills/use-ash_postgres/SKILL.md",
          old_skill_md
        )
        |> sync(skills: [location: ".claude/skills", deps: [:ash_postgres]])
        |> assert_creates(".claude/skills/use-ash-postgres/SKILL.md")

      assert ".claude/skills/use-ash_postgres/SKILL.md" in igniter.rms

      content = file_content(igniter, ".claude/skills/use-ash-postgres/SKILL.md")
      assert content =~ "name: use-ash-postgres"
      assert content =~ "managed-by: usage-rules"
    end

    test "emits warning for build spec with non-compliant name" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo"
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          build: [
            my_skill: [usage_rules: [:foo]]
          ]
        ]
      )
      |> assert_has_warning(fn warning ->
        String.contains?(warning, "must only contain lowercase letters")
      end)
    end

    test "emits warning for skill name exceeding 64 characters" do
      long_name = String.duplicate("a", 65)

      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo"
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          build: [
            {String.to_atom(long_name), [usage_rules: [:foo]]}
          ]
        ]
      )
      |> assert_has_warning(fn warning ->
        String.contains?(warning, "exceeds 64 characters")
      end)
    end

    test "emits warning for skill name with leading hyphen" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo"
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          build: [
            "-bad-name": [usage_rules: [:foo]]
          ]
        ]
      )
      |> assert_has_warning(fn warning ->
        String.contains?(warning, "must not start or end with a hyphen")
      end)
    end

    test "emits warning for skill name with consecutive hyphens" do
      project_with_deps(%{
        "deps/foo/usage-rules.md" => "# Foo"
      })
      |> sync(
        skills: [
          location: ".claude/skills",
          build: [
            "bad--name": [usage_rules: [:foo]]
          ]
        ]
      )
      |> assert_has_warning(fn warning ->
        String.contains?(warning, "must not contain consecutive hyphens")
      end)
    end

    test "emits warning for package skill with non-compliant name" do
      project_with_deps(%{
        "deps/foo/usage-rules/skills/bad_name/SKILL.md" =>
          "---\nname: bad_name\ndescription: \"A skill.\"\n---\nContent."
      })
      |> sync(skills: [location: ".claude/skills", package_skills: [:foo]])
      |> assert_has_warning(fn warning ->
        String.contains?(warning, "must only contain lowercase letters")
      end)
    end

    test "description longer than 1024 characters is truncated" do
      long_description = String.duplicate("x", 1100)

      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [
                usage_rules: [:foo],
                description: long_description
              ]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      # The description in the frontmatter should be truncated to 1024 chars max
      # (1021 chars + "...")
      refute content =~ String.duplicate("x", 1025)
      assert content =~ "..."
    end

    test "generated description within 1024 characters is not truncated" do
      igniter =
        project_with_deps(%{
          "deps/foo/usage-rules.md" => "# Foo"
        })
        |> sync(
          skills: [
            location: ".claude/skills",
            build: [
              "use-foo": [
                usage_rules: [:foo],
                description: "Short description."
              ]
            ]
          ]
        )
        |> assert_creates(".claude/skills/use-foo/SKILL.md")

      content = file_content(igniter, ".claude/skills/use-foo/SKILL.md")
      assert content =~ "Short description."
      refute content =~ "..."
    end
  end
end
