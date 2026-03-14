defmodule Mix.Tasks.Tak.List do
  @shortdoc "List all git worktrees with their status"
  @moduledoc """
  Lists all git worktrees with their port, database, and running status.

      $ mix tak.list

  Includes the main repository alongside every worktree in `trees/`. For each
  entry, status is determined by probing the configured port:

    * `RUNNING` — port is in use; shows the PID and a clickable URL
    * `STOPPED` — port is free
    * `UNKNOWN` — no port could be read from the worktree config

  A summary line at the end counts running vs. stopped worktrees.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    {main, worktrees} = Tak.Worktrees.list()

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, "Git Worktrees"]))
    Mix.shell().info("")

    render_main(main)

    if worktrees == [] do
      Mix.shell().info(IO.ANSI.format([:faint, "No worktrees found in #{Tak.trees_dir()}/"]))
      Mix.shell().info("")
      Mix.shell().info(IO.ANSI.format(["Create one with: ", :bright, "mix tak.create <branch-name>"]))
      Mix.shell().info("")
    else
      Enum.each(worktrees, &render_worktree/1)

      all = [main | worktrees]
      running = Enum.count(all, &(&1.status == :running))
      stopped = Enum.count(all, &(&1.status == :stopped))

      Mix.shell().info(
        IO.ANSI.format([
          :faint, "Summary: ",
          :green, "#{running} running",
          :reset, :faint, ", ",
          :red, "#{stopped} stopped"
        ])
      )

      Mix.shell().info("")
    end
  end

  defp render_main(entry) do
    branch = entry.branch || "unknown"
    Mix.shell().info(IO.ANSI.format([:bright, "main", :reset, " ", :faint, "(main repository)"]))
    Mix.shell().info("  Branch: #{branch}")
    Mix.shell().info("  Port:   #{entry.port}")
    render_status(entry)
    Mix.shell().info("")
  end

  defp render_worktree(entry) do
    branch = entry.branch || "unknown"
    Mix.shell().info(IO.ANSI.format([:bright, entry.name, :reset, " ", :faint, "(#{branch})"]))
    if entry.port, do: Mix.shell().info("  Port:     #{entry.port}")
    if entry.database, do: Mix.shell().info("  Database: #{entry.database}")
    render_status(entry)
    Mix.shell().info("")
  end

  defp render_status(entry) do
    {status_str, color} = format_status(entry.status)

    if entry.pid do
      Mix.shell().info(IO.ANSI.format(["  Status: ", color, status_str, :reset, :faint, " (PID: #{entry.pid})"]))
      Mix.shell().info("  URL:    http://localhost:#{entry.port}")
    else
      Mix.shell().info(IO.ANSI.format(["  Status: ", color, status_str]))
    end
  end

  defp format_status(:running), do: {"RUNNING", :green}
  defp format_status(:stopped), do: {"STOPPED", :red}
  defp format_status(:unknown), do: {"UNKNOWN", :yellow}
end
