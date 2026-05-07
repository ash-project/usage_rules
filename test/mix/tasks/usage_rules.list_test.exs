# SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.UsageRules.ListTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.UsageRules.List

  @builtin_note_prefix "Built-in config atoms :elixir and :otp pull :usage_rules sub-rules"

  describe "mix usage_rules.list (fixture project)" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "usage_rules_list_#{:erlang.unique_integer([:positive])}")

      File.rm_rf(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, tmp_dir: dir}
    end

    test "lists main file and sub-rules (discovers distinct sub-rule names)", %{tmp_dir: dir} do
      app = fixture_app!(dir, phx_style: :sub_rules, plain: :main_only)

      output =
        Mix.Project.in_project(app, dir, fn _ ->
          capture_io(fn -> List.run([]) end)
        end)

      assert output =~ "Dependencies with usage rules:"
      assert output =~ ":phx_style"
      assert output =~ "usage-rules.md: yes"
      assert output =~ "sub-rules: channels, routing"
      assert output =~ ":plain"
      assert output =~ "sub-rules: (none)"
      assert output =~ @builtin_note_prefix
    end

    test "filters by dependency name (colon, case)", %{tmp_dir: dir} do
      app = fixture_app!(dir, phx_style: :sub_rules)

      for argv <- [["phx_style"], ["Phx_Style"], [":phx_style"]] do
        output =
          Mix.Project.in_project(app, dir, fn _ ->
            capture_io(fn -> List.run(argv) end)
          end)

        assert output =~ ":phx_style"
        assert output =~ "sub-rules: channels, routing"
        refute output =~ ":plain"
      end
    end

    test "reports when filtered dependency has no usage rules", %{tmp_dir: dir} do
      app = fixture_app!(dir, phx_style: :sub_rules, bare: :empty)

      output =
        Mix.Project.in_project(app, dir, fn _ ->
          capture_io(fn -> List.run(["bare"]) end)
        end)

      assert output =~ "Dependency \"bare\" has no usage-rules.md or usage-rules/*.md."
      assert output =~ @builtin_note_prefix
    end

    test "lists dependency with only sub-rules (no usage-rules.md)", %{tmp_dir: dir} do
      app = fixture_app!(dir, only_subs: :subs_only)

      output =
        Mix.Project.in_project(app, dir, fn _ ->
          capture_io(fn -> List.run([]) end)
        end)

      assert output =~ ":only_subs"
      assert output =~ "usage-rules.md: no"
      assert output =~ "sub-rules: live_view"
    end
  end

  describe "mix usage_rules.list (errors)" do
    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "usage_rules_list_err_#{:erlang.unique_integer([:positive])}"
        )

      File.rm_rf(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, tmp_dir: dir}
    end

    test "raises when package is not a dependency", %{tmp_dir: dir} do
      app = fixture_app!(dir, phx_style: :sub_rules)

      assert_raise Mix.Error, ~r/No dependency matching/, fn ->
        Mix.Project.in_project(app, dir, fn _ ->
          List.run(["not_a_real_dependency_xyz"])
        end)
      end
    end

    test "accepts at most one package name", %{tmp_dir: dir} do
      app = fixture_app!(dir, phx_style: :sub_rules)

      assert_raise Mix.Error, ~r/at most one package name/, fn ->
        Mix.Project.in_project(app, dir, fn _ ->
          List.run(["phx_style", "bare"])
        end)
      end
    end
  end

  defp fixture_app!(dir, fixtures) do
    app = :"lr_lst_#{System.unique_integer([:positive])}"
    mod = Module.concat([Macro.camelize(Atom.to_string(app))])

    deps =
      fixtures
      |> Enum.map(fn {dep, kind} ->
        write_dep!(dir, dep, kind)
        {dep, "deps/#{dep}"}
      end)

    write_root_mix!(dir, mod, app, deps)
    app
  end

  defp write_root_mix!(dir, mod, app, deps) do
    dep_lines =
      Enum.map_join(deps, ",\n", fn {name, path} ->
        "      {#{inspect(name)}, path: #{inspect(path)}}"
      end)

    mix = """
    defmodule #{inspect(mod)}.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
      end

      def application, do: [extra_applications: [:logger]]

      defp deps do
        [
    #{dep_lines}
        ]
      end
    end
    """

    File.write!(Path.join(dir, "mix.exs"), mix)
  end

  defp write_dep!(dir, dep, kind) do
    base = Path.join([dir, "deps", to_string(dep)])
    File.mkdir_p!(base)

    File.write!(Path.join(base, "mix.exs"), dep_mix(dep))

    usage_dir = Path.join(base, "usage-rules")

    case kind do
      :sub_rules ->
        File.write!(Path.join(base, "usage-rules.md"), "# #{dep} main\n")
        File.mkdir_p!(usage_dir)
        File.mkdir_p!(Path.join(usage_dir, "skills"))
        File.write!(Path.join(usage_dir, "routing.md"), "# routes\n")
        File.write!(Path.join(usage_dir, "channels.md"), "# channels\n")
        File.write!(Path.join([usage_dir, "skills", "ignored.md"]), "# not top-level\n")

      :main_only ->
        File.write!(Path.join(base, "usage-rules.md"), "# plain\n")

      :empty ->
        :ok

      :subs_only ->
        File.mkdir_p!(usage_dir)
        File.write!(Path.join(usage_dir, "live_view.md"), "# lv\n")
    end
  end

  defp dep_mix(dep) do
    mod = Module.concat([Macro.camelize(Atom.to_string(dep))])

    """
    defmodule #{inspect(mod)}.MixProject do
      use Mix.Project
      def project do
        [app: #{inspect(dep)}, version: "0.1.0", deps: []]
      end
    end
    """
  end
end
