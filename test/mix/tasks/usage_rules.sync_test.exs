defmodule Mix.Tasks.UsageRules.SyncTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  describe "specific packages" do
    test "combines usage rules from specified packages into target file" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "phoenix"])
      |> assert_creates("rules.md")
    end

    test "ignores packages without usage-rules.md files" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "phoenix"])
      |> assert_creates("rules.md")
    end

    test "requires packages when no options given" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", [])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(error_message, "Usage:")
          assert String.contains?(error_message, "mix usage_rules.sync <file> <packages...>")

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end
  end

  describe "--all option" do
    test "includes all dependencies with usage-rules.md files" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules",
          "deps/ecto/usage-rules.md" => "Ecto database rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "--all"])
      |> assert_has_notice("Found 3 dependencies with usage rules")
      |> assert_has_notice("Including usage rules for: ash")
      |> assert_has_notice("Including usage rules for: ecto")
      |> assert_has_notice("Including usage rules for: phoenix")
      |> assert_creates("rules.md")
    end

    test "requires file when using --all option" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["--all"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(error_message, "--all option requires a file to write to")

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "cannot specify packages with --all option" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--all"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "Cannot specify packages when using --all or --list options"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end
  end

  describe "--list option" do
    test "lists all dependencies with usage rules without file comparison" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["--list"])
      |> assert_has_notice("ash: \e[32mhas usage rules\e[0m")
      |> assert_has_notice("phoenix: \e[32mhas usage rules\e[0m")
    end

    test "shows message when no packages have usage rules" do
      test_project()
      |> Igniter.compose_task("usage_rules.sync", ["--list"])
      |> assert_has_notice("No packages found with usage-rules.md files")
    end

    test "cannot specify packages with --list option" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--list"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "Cannot specify packages when using --all or --list options"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end
  end

  describe "file operations" do
    test "creates new file when file doesn't exist" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["new_rules.md", "ash"])
      |> assert_creates("new_rules.md")
    end

    test "handles empty usage-rules.md files" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => ""
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash"])
      |> assert_creates("rules.md")
    end

    test "handles package names with special characters" do
      test_project(
        files: %{
          "deps/special-pkg/usage-rules.md" => "Special package rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "special-pkg"])
      |> assert_creates("rules.md")
    end

    test "does not duplicate content when updating existing file with package rules" do
      test_project(
        files: %{
          "rules.md" => """
          # Existing Rules

          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          Old ash content
          <-- ash-end -->
          <-- usage-rules-end -->

          More content.
          """,
          "deps/ash_json_api/usage-rules.md" => "AshJsonApi usage rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash_json_api"])
      |> assert_content_equals("rules.md", """
      # Existing Rules

      <-- usage-rules-start -->
      <-- ash-start -->
      ## ash usage
      Old ash content
      <-- ash-end -->
      <-- ash_json_api-start -->
      ## ash_json_api usage
      AshJsonApi usage rules
      <-- ash_json_api-end -->
      <-- usage-rules-end -->

      More content.
      """)
    end

    test "does not duplicate ash_json_api when adding it twice" do
      test_project(
        files: %{
          "rules.md" => """
          # Existing Rules

          <-- usage-rules-start -->
          <-- ash_json_api-start -->
          ## ash_json_api usage
          Old AshJsonApi content
          <-- ash_json_api-end -->
          <-- usage-rules-end -->

          More content.
          """,
          "deps/ash_json_api/usage-rules.md" => "New AshJsonApi usage rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash_json_api"])
      |> assert_content_equals("rules.md", """
      # Existing Rules

      <-- usage-rules-start -->
      <-- ash_json_api-start -->
      ## ash_json_api usage
      New AshJsonApi usage rules
      <-- ash_json_api-end -->
      <-- usage-rules-end -->

      More content.
      """)
    end
  end

  describe "--remove option" do
    test "removes specified packages from file" do
      test_project(
        files: %{
          "rules.md" => """
          # My Rules

          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          Ash framework rules
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          Phoenix web framework rules
          <-- phoenix-end -->
          <-- usage-rules-end -->

          More content.
          """,
          "deps/ash/usage-rules.md" => "Ash framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--remove"])
      |> assert_content_equals("rules.md", """
      # My Rules

      <-- usage-rules-start -->
      <-- phoenix-start -->
      ## phoenix usage
      Phoenix web framework rules
      <-- phoenix-end -->
      <-- usage-rules-end -->

      More content.
      """)
    end

    test "removes all specified packages" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          Ash framework rules
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          Phoenix web framework rules
          <-- phoenix-end -->
          <-- ecto-start -->
          ## ecto usage
          Ecto database rules
          <-- ecto-end -->
          <-- usage-rules-end -->
          """
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "phoenix", "--remove"])
      |> assert_content_equals("rules.md", """
      <-- usage-rules-start -->
      <-- ecto-start -->
      ## ecto usage
      Ecto database rules
      <-- ecto-end -->
      <-- usage-rules-end -->
      """)
    end

    test "removes entire usage-rules section when empty" do
      test_project(
        files: %{
          "rules.md" => """
          # My Rules

          Some content before.

          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          Ash framework rules
          <-- ash-end -->
          <-- usage-rules-end -->

          Some content after.
          """
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--remove"])
      |> assert_content_equals("rules.md", """
      # My Rules

      Some content before.

      Some content after.
      """)
    end

    test "ignores packages not in file" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          Ash framework rules
          <-- ash-end -->
          <-- usage-rules-end -->
          """
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "phoenix", "--remove"])
      |> assert_content_equals("rules.md", """
      <-- usage-rules-start -->
      <-- ash-start -->
      ## ash usage
      Ash framework rules
      <-- ash-end -->
      <-- usage-rules-end -->
      """)
    end

    test "requires file to exist" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["nonexistent.md", "ash", "--remove"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(error_message, "File nonexistent.md does not exist")

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "requires packages to be specified" do
      igniter =
        test_project(files: %{"rules.md" => "content"})
        |> Igniter.compose_task("usage_rules.sync", ["rules.md", "--remove"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(error_message, "--remove option requires packages to remove")

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "requires file argument" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["--remove"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(error_message, "--remove option requires a file to remove from")

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "cannot be used with --all" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--remove", "--all"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "Cannot use --remove with --all or --list options"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "cannot be used with --list" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--remove", "--list"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "Cannot use --remove with --all or --list options"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end
  end

  describe "--link-to-folder option" do
    test "creates individual files in folder and links to them" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "ash",
        "phoenix",
        "--link-to-folder",
        "rules"
      ])
      |> assert_creates("rules.md")
      |> assert_creates("rules/ash.md")
      |> assert_creates("rules/phoenix.md")
      |> assert_content_equals("rules/ash.md", "Ash framework rules")
      |> assert_content_equals("rules/phoenix.md", "Phoenix web framework rules")
      |> assert_content_equals(
        "rules.md",
        """
        <-- usage-rules-start -->
        <-- ash-start -->
        ## ash usage
        [ash usage rules](rules/ash.md)
        <-- ash-end -->
        <-- phoenix-start -->
        ## phoenix usage
        [phoenix usage rules](rules/phoenix.md)
        <-- phoenix-end -->
        <-- usage-rules-end -->
        """
        |> String.trim_trailing()
      )
    end

    test "works with --all option" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules",
          "deps/ecto/usage-rules.md" => "Ecto database rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "--all",
        "--link-to-folder",
        "docs"
      ])
      |> assert_creates("rules.md")
      |> assert_creates("docs/ash.md")
      |> assert_creates("docs/ecto.md")
      |> assert_creates("docs/phoenix.md")
      |> assert_content_equals("docs/ash.md", "Ash framework rules")
      |> assert_content_equals("docs/ecto.md", "Ecto database rules")
      |> assert_content_equals("docs/phoenix.md", "Phoenix web framework rules")
    end

    test "creates @-style links when explicitly specified" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "ash",
        "phoenix",
        "--link-to-folder",
        "rules",
        "--link-style",
        "at"
      ])
      |> assert_creates("rules.md")
      |> assert_creates("rules/ash.md")
      |> assert_creates("rules/phoenix.md")
      |> assert_content_equals("rules/ash.md", "Ash framework rules")
      |> assert_content_equals("rules/phoenix.md", "Phoenix web framework rules")
      |> assert_content_equals(
        "rules.md",
        """
        <-- usage-rules-start -->
        <-- ash-start -->
        ## ash usage
        @rules/ash.md
        <-- ash-end -->
        <-- phoenix-start -->
        ## phoenix usage
        @rules/phoenix.md
        <-- phoenix-end -->
        <-- usage-rules-end -->
        """
        |> String.trim_trailing()
      )
    end

    test "updates existing folder files" do
      test_project(
        files: %{
          "rules.md" => """
          # Existing Rules

          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @rules/ash.md
          <-- ash-end -->
          <-- usage-rules-end -->

          More content.
          """,
          "rules/ash.md" => "Old ash content",
          "deps/ash/usage-rules.md" => "New ash content",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "ash",
        "phoenix",
        "--link-to-folder",
        "rules"
      ])
      |> assert_content_equals("rules/ash.md", "New ash content")
      |> assert_content_equals("rules/phoenix.md", "Phoenix web framework rules")
      |> assert_content_equals("rules.md", """
      # Existing Rules

      <-- usage-rules-start -->
      <-- ash-start -->
      ## ash usage
      [ash usage rules](rules/ash.md)
      <-- ash-end -->
      <-- phoenix-start -->
      ## phoenix usage
      [phoenix usage rules](rules/phoenix.md)
      <-- phoenix-end -->
      <-- usage-rules-end -->

      More content.
      """)
    end

    test "creates nested folder structure" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => "Ash framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "ash",
        "--link-to-folder",
        "docs/usage"
      ])
      |> assert_creates("rules.md")
      |> assert_creates("docs/usage/ash.md")
      |> assert_content_equals("docs/usage/ash.md", "Ash framework rules")
      |> assert_content_equals(
        "rules.md",
        """
        <-- usage-rules-start -->
        <-- ash-start -->
        ## ash usage
        [ash usage rules](docs/usage/ash.md)
        <-- ash-end -->
        <-- usage-rules-end -->
        """
        |> String.trim_trailing()
      )
    end

    test "handles packages with special characters in folder names" do
      test_project(
        files: %{
          "deps/special-pkg/usage-rules.md" => "Special package rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "special-pkg",
        "--link-to-folder",
        "rules"
      ])
      |> assert_creates("rules.md")
      |> assert_creates("rules/special-pkg.md")
      |> assert_content_equals("rules/special-pkg.md", "Special package rules")
    end

    test "works with --remove to remove folder files" do
      test_project(
        files: %{
          "rules.md" => """
          # My Rules

          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @rules/ash.md
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          @rules/phoenix.md
          <-- phoenix-end -->
          <-- usage-rules-end -->

          More content.
          """,
          "rules/ash.md" => "Ash framework rules",
          "rules/phoenix.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "ash",
        "--remove",
        "--link-to-folder",
        "rules"
      ])
      |> assert_content_equals("rules.md", """
      # My Rules

      <-- usage-rules-start -->
      <-- phoenix-start -->
      ## phoenix usage
      @rules/phoenix.md
      <-- phoenix-end -->
      <-- usage-rules-end -->

      More content.
      """)

      # Note: This test also deletes the individual rules/ash.md file
      # but only verifies the main file content for simplicity
    end

    test "works with --list to check folder link status" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @rules/ash.md
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          @rules/phoenix.md
          <-- phoenix-end -->
          <-- usage-rules-end -->
          """,
          "rules/ash.md" => "Ash framework rules",
          "rules/phoenix.md" => "Phoenix web framework rules",
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "--list",
        "--link-to-folder",
        "rules"
      ])
      |> assert_has_notice("ash: \e[32mpresent\e[0m")
      |> assert_has_notice("phoenix: \e[32mpresent\e[0m")
    end

    test "shows stale status when linked folder file doesn't match" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @rules/ash.md
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          @rules/phoenix.md
          <-- phoenix-end -->
          <-- usage-rules-end -->
          """,
          "rules/ash.md" => "Old Ash framework rules",
          "rules/phoenix.md" => "Phoenix web framework rules",
          "deps/ash/usage-rules.md" => "New Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "--list",
        "--link-to-folder",
        "rules"
      ])
      |> assert_has_notice("ash: \e[33mstale\e[0m")
      |> assert_has_notice("phoenix: \e[32mpresent\e[0m")
    end

    test "shows stale status when linked folder file doesn't exist" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @rules/ash.md
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          @rules/phoenix.md
          <-- phoenix-end -->
          <-- usage-rules-end -->
          """,
          "rules/phoenix.md" => "Phoenix web framework rules",
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "--list",
        "--link-to-folder",
        "rules"
      ])
      |> assert_has_notice("ash: \e[33mstale\e[0m")
      |> assert_has_notice("phoenix: \e[32mpresent\e[0m")
    end

    test "requires a file to write to" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", ["--link-to-folder", "ash"])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "--link-to-folder option requires a file to write to"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "links directly to deps files when folder is 'deps'" do
      igniter =
        test_project(
          files: %{
            "deps/ash/usage-rules.md" => "Ash framework rules",
            "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
          }
        )
        |> Igniter.compose_task("usage_rules.sync", [
          "rules.md",
          "ash",
          "phoenix",
          "--link-to-folder",
          "deps"
        ])
        |> apply_igniter!()

      # Check that rules.md was created with correct content
      {:ok, rules_source} = Rewrite.source(igniter.rewrite, "rules.md")
      rules_content = Rewrite.Source.get(rules_source, :content)

      expected_content =
        """
        <-- usage-rules-start -->
        <-- ash-start -->
        ## ash usage
        [ash usage rules](deps/ash/usage-rules.md)
        <-- ash-end -->
        <-- phoenix-start -->
        ## phoenix usage
        [phoenix usage rules](deps/phoenix/usage-rules.md)
        <-- phoenix-end -->
        <-- usage-rules-end -->
        """
        |> String.trim_trailing()

      assert rules_content == expected_content

      # Check that individual files were NOT created
      assert {:error, _} = Rewrite.source(igniter.rewrite, "deps/ash.md")
      assert {:error, _} = Rewrite.source(igniter.rewrite, "deps/phoenix.md")
    end

    test "links directly to deps files with @-style when using --link-style at" do
      igniter =
        test_project(
          files: %{
            "deps/ash/usage-rules.md" => "Ash framework rules",
            "deps/phoenix/usage-rules.md" => "Phoenix web framework rules"
          }
        )
        |> Igniter.compose_task("usage_rules.sync", [
          "rules.md",
          "ash",
          "phoenix",
          "--link-to-folder",
          "deps",
          "--link-style",
          "at"
        ])
        |> apply_igniter!()

      # Check that rules.md was created with correct content
      {:ok, rules_source} = Rewrite.source(igniter.rewrite, "rules.md")
      rules_content = Rewrite.Source.get(rules_source, :content)

      expected_content =
        """
        <-- usage-rules-start -->
        <-- ash-start -->
        ## ash usage
        @deps/ash/usage-rules.md
        <-- ash-end -->
        <-- phoenix-start -->
        ## phoenix usage
        @deps/phoenix/usage-rules.md
        <-- phoenix-end -->
        <-- usage-rules-end -->
        """
        |> String.trim_trailing()

      assert rules_content == expected_content

      # Check that individual files were NOT created
      assert {:error, _} = Rewrite.source(igniter.rewrite, "deps/ash.md")
      assert {:error, _} = Rewrite.source(igniter.rewrite, "deps/phoenix.md")
    end

    test "validates link-style option values" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", [
          "rules.md",
          "ash",
          "--link-to-folder",
          "rules",
          "--link-style",
          "invalid"
        ])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "--link-style must be either 'markdown' or 'at'"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "requires link-to-folder when using link-style" do
      igniter =
        test_project()
        |> Igniter.compose_task("usage_rules.sync", [
          "rules.md",
          "ash",
          "--link-style",
          "at"
        ])

      case apply_igniter(igniter) do
        {:error, [error_message]} ->
          assert String.contains?(
                   error_message,
                   "--link-style can only be used with --link-to-folder"
                 )

        result ->
          flunk("Expected error, got: #{inspect(result)}")
      end
    end

    test "handles empty usage-rules.md files in folder mode" do
      test_project(
        files: %{
          "deps/ash/usage-rules.md" => ""
        }
      )
      |> Igniter.compose_task("usage_rules.sync", ["rules.md", "ash", "--link-to-folder", "rules"])
      |> assert_creates("rules.md")
      |> assert_creates("rules/ash.md")
      |> assert_content_equals("rules/ash.md", "")
    end

    test "works with --all and --list with --link-to-folder" do
      test_project(
        files: %{
          "rules.md" => """
          <-- usage-rules-start -->
          <-- ash-start -->
          ## ash usage
          @docs/ash.md
          <-- ash-end -->
          <-- phoenix-start -->
          ## phoenix usage
          @docs/phoenix.md
          <-- phoenix-end -->
          <-- usage-rules-end -->
          """,
          "docs/ash.md" => "Ash framework rules",
          "deps/ash/usage-rules.md" => "Ash framework rules",
          "deps/phoenix/usage-rules.md" => "Phoenix web framework rules",
          "deps/ecto/usage-rules.md" => "Ecto database rules"
        }
      )
      |> Igniter.compose_task("usage_rules.sync", [
        "rules.md",
        "--list",
        "--link-to-folder",
        "docs"
      ])
      |> assert_has_notice("ash: \e[32mpresent\e[0m")
      |> assert_has_notice("ecto: \e[31mmissing\e[0m")
      |> assert_has_notice("phoenix: \e[33mstale\e[0m")
    end
  end
end
