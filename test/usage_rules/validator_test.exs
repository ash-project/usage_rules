# SPDX-FileCopyrightText: 2026 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule UsageRules.ValidatorTest do
  # The validator reads ex_doc's global "warned?" persistent_term flag, so
  # validation runs must not overlap.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Persistent term state from other mixes of ex_doc (e.g. other test
  # processes) must not leak between tests.
  setup do
    :persistent_term.erase({ExDoc, :warned?})
    :ok
  end

  defp validate!(contents) when is_map(contents) do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "usage_rules_validator_test",
        Integer.to_string(System.unique_integer([:positive]))
      ])

    File.mkdir_p!(tmp_dir)

    paths =
      Enum.map(contents, fn {name, content} ->
        path = Path.join(tmp_dir, name)
        File.write!(path, content)
        path
      end)

    warnings =
      capture_io(:stderr, fn ->
        send(self(), {:result, UsageRules.Validator.validate(paths)})
      end)

    result = receive(do: ({:result, result} -> result))

    {warnings, result, tmp_dir}
  end

  describe "native ex_doc checks" do
    test "warns about undefined and bad-arity function references" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          See `Enum.definitely_not_real/2` and `Enum.map/9`.
          """
        })

      assert result.warned?
      assert warnings =~ "documentation references function \"Enum.definitely_not_real/2\""
      assert warnings =~ "undefined or private"
      assert warnings =~ "documentation references function \"Enum.map/9\""
      assert warnings =~ "rules.md:1"
    end

    test "warns about hidden (@doc false / @moduledoc false) targets" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          Docs: `Mix.Tasks.UsageRules.Sync.Docs`
          """
        })

      assert result.warned?
      assert warnings =~ "documentation references module \"Mix.Tasks.UsageRules.Sync.Docs\""
      assert warnings =~ "hidden"

      # reported exactly once — the native pass, with no complements
      assert warnings |> String.split("documentation references module") |> tl() |> length() == 1
    end

    test "warns about broken backtick reference links" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          See [`Fake`](`NoSuch.Module.Xyz`) and [`good`](`Enum`).
          """
        })

      assert result.warned?
      assert warnings =~ "documentation references module \"NoSuch.Module.Xyz\""
    end

    test "warns about links to files outside the validated set" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          [missing](other.md) and [present](exists.md).
          """,
          "exists.md" => "exists\n"
        })

      assert result.warned?
      assert warnings =~ "documentation references file \"other.md\""
      refute warnings =~ "documentation references file \"exists.md\""
    end

    test "does not warn about valid references" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          Use `Enum.map/2`, read about `Enum`, see [`docs`](`Enum`) and [this file](rules.md).
          """
        })

      refute result.warned?
      assert warnings == ""
    end
  end

  describe "documented ex_doc gaps (no warnings, by design)" do
    test "fenced code blocks are not checked, matching ex_doc" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          ```elixir
          NoSuch.Module.InFence = :ok
          ```
          """
        })

      refute result.warned?
      assert warnings == ""
    end

    test "bare undefined module mentions in plain code spans stay silent, like in moduledocs" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          See `NoSuch.Module.Xyz` in prose.
          """
        })

      refute result.warned?
      assert warnings == ""
    end

    test "mix task mentions in plain code spans stay silent, like in moduledocs" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          Run `mix definitely_not_a_real_task`.
          """
        })

      refute result.warned?
      assert warnings == ""
    end

    test "single segments, atoms, lowercase chains, and file names are not module references" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          `Enum` and `:ok` and `foo.bar` and `SKILL.md` and `README`.
          """
        })

      refute result.warned?
      assert warnings == ""
    end
  end

  describe "validate/1" do
    test "returns the validated file paths" do
      {_warnings, result, _tmp_dir} =
        validate!(%{"a.md" => "clean\n", "b.md" => "also clean\n"})

      assert length(result.files) == 2
      assert Enum.all?(result.files, &String.ends_with?(&1, ".md"))
    end

    test "erlang function references are validated" do
      {warnings, result, _tmp_dir} =
        validate!(%{
          "rules.md" => """
          Use `:timer.definitely_not_real/1`.
          """
        })

      assert result.warned?
      assert warnings =~ ":timer.definitely_not_real/1"
    end
  end

  describe "ensure_ex_doc!/1" do
    test "passes when ex_doc is compiled and started" do
      assert :ok = UsageRules.Validator.ensure_ex_doc!()
    end

    test "fails with an actionable error when ex_doc is not compiled" do
      exception =
        assert_raise Mix.Error, fn ->
          UsageRules.Validator.ensure_ex_doc!(fn _ -> {:error, :nofile} end)
        end

      message = Exception.message(exception)

      assert message =~ "ex_doc"
      assert message =~ "not compiled and available"
      assert message =~ "mix deps.get"
      assert message =~ "mix deps.compile"
    end
  end
end
