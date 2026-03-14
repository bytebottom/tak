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
    entries = Tak.Worktrees.list()

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, "Git Worktrees"]))
    Mix.shell().info("")

    if Enum.count(entries) == 1 do
      render_entry(hd(entries))
      Mix.shell().info(IO.ANSI.format([:faint, "No worktrees found in #{Tak.trees_dir()}/"]))
      Mix.shell().info("")
      Mix.shell().info(IO.ANSI.format(["Create one with: ", :bright, "mix tak.create <branch-name>"]))
      Mix.shell().info("")
    else
      running = Enum.count(entries, &(&1.status == :running))
      stopped = Enum.count(entries, &(&1.status == :stopped))

      Enum.each(entries, &render_entry/1)

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

  defp render_entry(entry) do
    label = if entry.main?, do: "(main repository)", else: "(#{entry.branch || "unknown"})"
    Mix.shell().info(IO.ANSI.format([:bright, entry.name, :reset, " ", :faint, label]))

    if entry[:main?] do
      Mix.shell().info("  Branch: #{entry.branch || "unknown"}")
      Mix.shell().info("  Port:   #{entry.port}")
    else
      if entry.port, do: Mix.shell().info("  Port:     #{entry.port}")
      if entry.database, do: Mix.shell().info("  Database: #{entry.database}")
    end

    {status_str, color} = format_status(entry.status)

    if entry.pid do
      Mix.shell().info(IO.ANSI.format(["  Status: ", color, status_str, :reset, :faint, " (PID: #{entry.pid})"]))
      Mix.shell().info("  URL:    http://localhost:#{entry.port}")
    else
      Mix.shell().info(IO.ANSI.format(["  Status: ", color, status_str]))
    end

    Mix.shell().info("")
  end

  defp format_status(:running), do: {"RUNNING", :green}
  defp format_status(:stopped), do: {"STOPPED", :red}
  defp format_status(:unknown), do: {"UNKNOWN", :yellow}
end
