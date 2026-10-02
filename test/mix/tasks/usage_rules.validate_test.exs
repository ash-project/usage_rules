# SPDX-FileCopyrightText: 2026 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.ValidateTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.UsageRules.Validate

  test "prints a notice when no rules-managed files exist" do
    output = capture_io(fn -> Validate.run([]) end)

    assert output =~ "No usage-rules-managed files found"
    assert output =~ "pass file paths to validate"
  end

  test "prints usage for --help" do
    output = capture_io(fn -> Validate.run(["--help"]) end)

    assert output =~ "mix usage_rules.validate"
    assert output =~ "[files...]"
  end

  test "raises on invalid options" do
    assert_raise Mix.Error, ~r/Invalid options/, fn ->
      capture_io(fn -> Validate.run(["--bogus"]) end)
    end
  end

  @tag :tmp_dir
  test "raises naming each pattern that matches no files", %{tmp_dir: tmp_dir} do
    existing = Path.join(tmp_dir, "exists.md")
    File.write!(existing, "# Exists\n")
    missing_glob = Path.join(tmp_dir, "nope/*.md")
    missing_file = Path.join(tmp_dir, "missing.md")

    error =
      assert_raise Mix.Error, fn ->
        capture_io(fn -> Validate.run([existing, missing_glob, missing_file]) end)
      end

    assert error.message =~ "No files matched"
    assert error.message =~ inspect(missing_glob)
    assert error.message =~ inspect(missing_file)
    refute error.message =~ inspect(existing)
  end

  @tag :tmp_dir
  test "treats a pattern matching only directories as matching no files", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "dir.md"))
    pattern = Path.join(tmp_dir, "*.md")

    assert_raise Mix.Error, ~r/No files matched: #{Regex.escape(inspect(pattern))}/, fn ->
      capture_io(fn -> Validate.run([pattern]) end)
    end
  end

  @tag :tmp_dir
  test "treats an existing file name containing glob characters literally", %{tmp_dir: tmp_dir} do
    file = Path.join(tmp_dir, "[draft].md")
    File.write!(file, "# Draft\n")

    output = capture_io(fn -> Validate.run([file]) end)

    refute output =~ "No files matched"
  end
end
