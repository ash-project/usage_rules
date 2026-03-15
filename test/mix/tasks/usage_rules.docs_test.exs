# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.DocsTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.UsageRules.Docs

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end

  test "shows documentation for a module" do
    output = capture_io(fn ->
      Docs.run(["Enum"])
    end) |> strip_ansi()

    assert output =~ "Searching local docs for"
    assert output =~ "Enum"
    assert output =~ "Functions for working with collections"
  end

  test "shows documentation for a function" do
    output = capture_io(fn ->
      Docs.run(["Enum.map/2"])
    end) |> strip_ansi()

    assert output =~ "Searching local docs for"
    assert output =~ "Enum.map/2"
    assert output =~ "Returns a list where each element is the result of invoking"
  end

  test "shows documentation for a callback" do
    output = capture_io(fn ->
      Docs.run(["GenServer.handle_call"])
    end) |> strip_ansi()

    assert output =~ "Searching local docs for"
    assert output =~ "GenServer.handle_call"
    assert output =~ "Invoked to handle synchronous call/3 messages"
    refute output =~ "No documentation for function GenServer.handle_call was found"
  end

  test "handles invalid expressions" do
    assert_raise Mix.Error, ~r/Invalid module or function/, fn ->
      Docs.run(["invalid expression"])
    end
  end

  test "handles non-existent modules" do
    output = capture_io(fn ->
      Docs.run(["NonExistentModule"])
    end)

    assert output =~ "Could not load module NonExistentModule"
  end
end
