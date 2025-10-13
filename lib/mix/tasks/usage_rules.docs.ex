# SPDX-FileCopyrightText: 2025 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.Docs do
  use Mix.Task

  @shortdoc "Shows documentation for Elixir modules and functions"

  @moduledoc """
  Shows documentation for Elixir modules and functions in markdown format.

  ## Examples

  Show documentation for a module:
      $ mix usage_rules.docs Enum

  Show documentation for a function:
      $ mix usage_rules.docs Enum.map/2

  Show documentation for a nested module:
      $ mix usage_rules.docs MyApp.User.Helpers
  """

  require Logger

  @impl true
  def run([module = <<first, _::binary>>]) when first in ?A..?Z or first == ?: do
    loadpaths!()

    iex_colors = Application.get_env(:iex, :colors, [])
    mix_colors = Application.get_env(:mix, :colors, [])

    try do
      Application.put_env(:iex, :colors, mix_colors)

      quoted =
        try do
          module
          |> Code.string_to_quoted!()
        rescue
          _ ->
            nil
        end

      quoted
      |> IEx.Introspection.decompose(__ENV__)
      |> case do
        :error ->
          Mix.raise("Invalid expression: #{module}")

        _decomposition ->
          Code.eval_quoted(
            quote do
              require IEx.Helpers

              IEx.Helpers.h(unquote(quoted))
            end
          )
      end
    after
      Application.put_env(:iex, :colors, iex_colors)
    end
  end

  def run([]) do
    raise_bad_args!()
  end

  def run([term | _]) do
    Mix.raise("Invalid module or function: #{term}")
  end

  # Loadpaths without checks because tasks may be defined in deps.
  defp loadpaths! do
    args = [
      "--no-elixir-version-check",
      "--no-deps-check",
      "--no-archives-check",
      "--no-listeners"
    ]

    Mix.Task.run("loadpaths", args)
    Mix.Task.reenable("loadpaths")
    Mix.Task.reenable("deps.loadpaths")
  end

  @spec raise_bad_args!() :: no_return()
  defp raise_bad_args! do
    Mix.raise("""
    Must provide a module or function. For example:
        $ mix usage_rules.docs Enum
        $ mix usage_rules.docs Enum.map/2
    """)
  end
end
