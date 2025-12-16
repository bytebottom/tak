defmodule Mix.Tasks.Tak.Doctor do
  @shortdoc "Check if the project is configured for tak"
  @moduledoc """
  Checks if the project is properly configured for tak worktrees.

      $ mix tak.doctor

  This will verify:

    * `config/config.exs` imports `dev.local.exs` (for dev env)
    * `config/dev.local.exs` is in `.gitignore`
    * `mise.local.toml` is in `.gitignore`
    * `trees/` directory is in `.gitignore`
    * Required tools are available (git, dropdb)

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
      check_mise_local_gitignore(),
      check_trees_gitignore(),
      check_git(),
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
    config_path = "config/config.exs"

    cond do
      not File.exists?(config_path) ->
        print_check(:error, "config/config.exs exists", "File not found")
        :error

      true ->
        content = File.read!(config_path)

        if String.contains?(content, "dev.local.exs") do
          print_check(:ok, "config/config.exs imports dev.local.exs")
          :ok
        else
          print_check(:error, "config/config.exs imports dev.local.exs", "Missing import")
          print_fix("""
          Add to config/config.exs:

              if config_env() == :dev and File.exists?(Path.expand("dev.local.exs", __DIR__)) do
                import_config "dev.local.exs"
              end

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

  defp check_mise_local_gitignore do
    check_gitignore_optional("mise.local.toml", "mise.local.toml", "only needed if using mise")
  end

  defp check_trees_gitignore do
    trees_dir = Tak.trees_dir()
    check_gitignore(trees_dir, "#{trees_dir}/")
  end

  defp check_gitignore(pattern, display) do
    case gitignore_contains?(pattern) do
      {:ok, true} ->
        print_check(:ok, "#{display} in .gitignore")
        :ok

      {:ok, false} ->
        print_check(:error, "#{display} in .gitignore", "Not ignored")
        print_fix("Add to .gitignore:\n\n    #{display}")
        :error

      {:error, reason} ->
        print_check(:error, "#{display} in .gitignore", reason)
        :error
    end
  end

  defp check_gitignore_optional(pattern, display, note) do
    case gitignore_contains?(pattern) do
      {:ok, true} ->
        print_check(:ok, "#{display} in .gitignore")
        :ok

      {:ok, false} ->
        print_check(:warn, "#{display} in .gitignore", note)
        :ok

      {:error, _reason} ->
        # Don't fail for optional checks if .gitignore doesn't exist
        print_check(:warn, "#{display} in .gitignore", note)
        :ok
    end
  end

  defp gitignore_contains?(pattern) do
    gitignore_path = ".gitignore"

    if not File.exists?(gitignore_path) do
      {:error, ".gitignore not found"}
    else
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

      {:ok, ignored}
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
