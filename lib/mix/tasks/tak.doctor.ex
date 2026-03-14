defmodule Mix.Tasks.Tak.Doctor do
  @shortdoc "Check if the project is configured for tak"
  @moduledoc """
  Validates that the project is ready to use tak worktrees.

      $ mix tak.doctor

  Runs the following checks and prints a pass/warn/fail result for each:

    * `config/config.exs` imports `*.local.exs` overrides
    * `config/dev.local.exs` is listed in `.gitignore`
    * `mise.local.toml` is listed in `.gitignore` (warning only; only needed if using mise)
    * `trees/` directory is listed in `.gitignore`
    * `git` executable is available
    * `dropdb` executable is available (warning only; only needed for `mix tak.remove`)

  For any failing check, the output includes the exact fix to apply. Warnings
  don't count as failures: the task exits cleanly as long as all non-optional
  checks pass.

  Run this before your first `mix tak.create` on a new project.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    {passed, failed, results} = Tak.Worktrees.doctor()

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, "Tak Doctor"]))
    Mix.shell().info("")

    Enum.each(results, &render_result/1)

    Mix.shell().info("")

    if failed == 0 do
      Mix.shell().info(IO.ANSI.format([:green, "All checks passed!"]))
    else
      Mix.shell().info(IO.ANSI.format([:yellow, "#{passed} passed, #{failed} failed"]))
    end

    Mix.shell().info("")
  end

  defp render_result({:ok, message}) do
    Mix.shell().info(IO.ANSI.format([:green, "✓ ", :reset, message]))
  end

  defp render_result({:error, message, reason}) do
    Mix.shell().info(IO.ANSI.format([:red, "✗ ", :reset, message, :faint, " — #{reason}"]))
    render_fix(message)
  end

  defp render_result({:warn, message, reason}) do
    Mix.shell().info(IO.ANSI.format([:yellow, "! ", :reset, message, :faint, " — #{reason}"]))
  end

  defp render_fix("config/config.exs imports local overrides") do
    print_fix("""
    Add to the end of config/config.exs:

        if File.exists?("\#{__DIR__}/\#{config_env()}.local.exs") do
          import_config "\#{config_env()}.local.exs"
        end
    """)
  end

  defp render_fix(message) do
    if String.contains?(message, ".gitignore") do
      pattern = message |> String.replace(" in .gitignore", "")
      print_fix("Add to .gitignore:\n\n    #{pattern}")
    end
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
