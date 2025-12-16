defmodule Mix.Tasks.Tak.List do
  @shortdoc "List all git worktrees with their status"
  @moduledoc """
  Lists all git worktrees with their configuration and status.

      $ mix tak.list

  Shows for each worktree:

    * Branch name
    * Port number
    * Database name
    * Running status (with PID if running)
    * URL if running

  ## Examples

      $ mix tak.list

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    trees_dir = Tak.trees_dir()
    base_port = Tak.base_port()

    running = 0
    stopped = 0

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, "Git Worktrees"]))
    Mix.shell().info("")

    # Main repository
    main_branch = get_current_branch()
    {main_status, main_color, running, stopped} = check_status(base_port, running, stopped)

    Mix.shell().info(IO.ANSI.format([:bright, "main", :reset, " ", :faint, "(main repository)"]))
    Mix.shell().info("  Branch: #{main_branch}")
    Mix.shell().info("  Port:   #{base_port}")
    Mix.shell().info(IO.ANSI.format(["  Status: ", main_color, main_status]))
    Mix.shell().info("")

    # Check if trees directory exists
    unless File.dir?(trees_dir) do
      Mix.shell().info(IO.ANSI.format([:faint, "No worktrees found in #{trees_dir}/"]))
      Mix.shell().info("")
      Mix.shell().info(IO.ANSI.format(["Create one with: ", :bright, "mix tak.create <branch-name>"]))
      exit(:normal)
    end

    # List worktrees
    worktrees = trees_dir |> File.ls!() |> Enum.filter(&File.dir?(Path.join(trees_dir, &1)))

    if Enum.empty?(worktrees) do
      Mix.shell().info(IO.ANSI.format([:faint, "No worktrees found in #{trees_dir}/"]))
      Mix.shell().info("")
      Mix.shell().info(IO.ANSI.format(["Create one with: ", :bright, "mix tak.create <branch-name>"]))
      exit(:normal)
    end

    {running, stopped} =
      Enum.reduce(worktrees, {running, stopped}, fn name, {running_acc, stopped_acc} ->
        worktree_path = Path.join(trees_dir, name)
        branch = Tak.get_worktree_branch(worktree_path) || "unknown"
        port = Tak.get_worktree_port(worktree_path)
        database = Tak.database_for(name)

        {status, color, running_acc, stopped_acc} = check_status(port, running_acc, stopped_acc)
        pid = if status == "RUNNING", do: Tak.pid_on_port(port), else: nil

        Mix.shell().info(IO.ANSI.format([:bright, name, :reset, " ", :faint, "(#{branch})"]))

        if port, do: Mix.shell().info("  Port:     #{port}")
        Mix.shell().info("  Database: #{database}")

        if pid do
          Mix.shell().info(IO.ANSI.format(["  Status:   ", color, status, :reset, :faint, " (PID: #{pid})"]))
          Mix.shell().info("  URL:      http://localhost:#{port}")
        else
          Mix.shell().info(IO.ANSI.format(["  Status:   ", color, status]))
        end

        Mix.shell().info("")

        {running_acc, stopped_acc}
      end)

    Mix.shell().info(
      IO.ANSI.format([
        :faint,
        "Summary: ",
        :green,
        "#{running} running",
        :reset,
        :faint,
        ", ",
        :red,
        "#{stopped} stopped"
      ])
    )

    Mix.shell().info("")
  end

  defp get_current_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> "unknown"
    end
  end

  defp check_status(nil, running, stopped), do: {"UNKNOWN", :yellow, running, stopped}

  defp check_status(port, running, stopped) do
    if Tak.port_in_use?(port) do
      {"RUNNING", :green, running + 1, stopped}
    else
      {"STOPPED", :red, running, stopped + 1}
    end
  end
end
