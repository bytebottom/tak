defmodule Mix.Tasks.Tak.Doctor do
  @shortdoc "Check if the project is configured for tak"
  @moduledoc """
  Checks if the project is properly configured for tak worktrees.

      $ mix tak.doctor

  This will verify:

    * `config/dev.exs` imports `dev.local.exs`
    * `config/dev.local.exs` is in `.gitignore`
    * `trees/` directory is in `.gitignore`
    * Required tools are available (git, mise, dropdb)

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, "Tak Doctor"]))
    Mix.shell().info("")

    checks = [
      check_dev_local_import(),
      check_dev_local_gitignore(),
      check_trees_gitignore(),
      check_git(),
      check_mise(),
      check_dropdb()
    ]

    passed = Enum.count(checks, &(&1 == :ok))
    failed = Enum.count(checks, &(&1 == :error))

    Mix.shell().info("")

    if failed == 0 do
      Mix.shell().info(IO.ANSI.format([:green, "All checks passed!"]))
    else
      Mix.shell().info(
        IO.ANSI.format([
          :yellow,
          "#{passed} passed, #{failed} failed"
        ])
      )
    end

    Mix.shell().info("")
  end

  defp check_dev_local_import do
    path = "config/dev.exs"

    cond do
      not File.exists?(path) ->
        print_check(:error, "config/dev.exs exists", "File not found")
        :error

      true ->
        content = File.read!(path)

        if String.contains?(content, "dev.local.exs") do
          print_check(:ok, "config/dev.exs imports dev.local.exs")
          :ok
        else
          print_check(:error, "config/dev.exs imports dev.local.exs", "Missing import")
          print_fix("""
          Add to the end of config/dev.exs:

              import_config "dev.local.exs"

          Then create an empty config/dev.local.exs:

              import Config
          """)

          :error
        end
    end
  end

  defp check_dev_local_gitignore do
    check_gitignore("dev.local.exs", "config/dev.local.exs")
  end

  defp check_trees_gitignore do
    trees_dir = Tak.trees_dir()
    check_gitignore(trees_dir, "#{trees_dir}/")
  end

  defp check_gitignore(pattern, display) do
    gitignore_path = ".gitignore"

    cond do
      not File.exists?(gitignore_path) ->
        print_check(:error, "#{display} in .gitignore", ".gitignore not found")
        :error

      true ->
        content = File.read!(gitignore_path)
        lines = String.split(content, "\n")

        # Check for the pattern or wildcards that would match
        ignored =
          Enum.any?(lines, fn line ->
            line = String.trim(line)

            cond do
              String.starts_with?(line, "#") -> false
              line == "" -> false
              String.contains?(line, pattern) -> true
              line == "/#{pattern}" -> true
              line == "#{pattern}" -> true
              true -> false
            end
          end)

        if ignored do
          print_check(:ok, "#{display} in .gitignore")
          :ok
        else
          print_check(:error, "#{display} in .gitignore", "Not ignored")
          print_fix("Add to .gitignore:\n\n    #{display}")
          :error
        end
    end
  end

  defp check_git do
    case System.cmd("which", ["git"], stderr_to_stdout: true) do
      {_, 0} ->
        print_check(:ok, "git available")
        :ok

      _ ->
        print_check(:error, "git available", "Not found")
        :error
    end
  end

  defp check_mise do
    case System.cmd("which", ["mise"], stderr_to_stdout: true) do
      {_, 0} ->
        print_check(:ok, "mise available")
        :ok

      _ ->
        print_check(:warn, "mise available", "Not found (optional, for port config)")
        :ok
    end
  end

  defp check_dropdb do
    case System.cmd("which", ["dropdb"], stderr_to_stdout: true) do
      {_, 0} ->
        print_check(:ok, "dropdb available")
        :ok

      _ ->
        print_check(:warn, "dropdb available", "Not found (needed for tak.remove)")
        :ok
    end
  end

  defp print_check(:ok, message) do
    Mix.shell().info(IO.ANSI.format([:green, "✓ ", :reset, message]))
  end

  defp print_check(:error, message, reason) do
    Mix.shell().info(IO.ANSI.format([:red, "✗ ", :reset, message, :faint, " — #{reason}"]))
  end

  defp print_check(:warn, message, reason) do
    Mix.shell().info(IO.ANSI.format([:yellow, "! ", :reset, message, :faint, " — #{reason}"]))
  end

  defp print_fix(message) do
    lines = message |> String.trim() |> String.split("\n")

    Mix.shell().info(IO.ANSI.format([:faint, "  Fix:"]))

    Enum.each(lines, fn line ->
      Mix.shell().info(IO.ANSI.format([:faint, "  #{line}"]))
    end)

    Mix.shell().info("")
  end
end
