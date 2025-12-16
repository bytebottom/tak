defmodule Mix.Tasks.Tak.Remove do
  @shortdoc "Remove a git worktree and clean up resources"
  @moduledoc """
  Removes a git worktree and cleans up associated resources.

      $ mix tak.remove <name> [--force]

  This will:

    * Stop any running services on the worktree's port
    * Remove the git worktree
    * Delete the git branch (if merged, or with --force)
    * Drop the associated database

  ## Arguments

    * `name` - The worktree name to remove (required)
    * `--force` - Force removal even with uncommitted changes

  ## Examples

      $ mix tak.remove armstrong
      $ mix tak.remove armstrong --force

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, strict: [force: :boolean])
    force = Keyword.get(opts, :force, false)

    case args do
      [] ->
        Mix.shell().error("Usage: mix tak.remove <name> [--force]")
        list_available_worktrees()
        exit({:shutdown, 1})

      [name | _] ->
        remove_worktree(name, force)
    end
  end

  defp list_available_worktrees do
    trees_dir = Tak.trees_dir()

    if File.dir?(trees_dir) do
      worktrees = trees_dir |> File.ls!() |> Enum.filter(&File.dir?(Path.join(trees_dir, &1)))

      unless Enum.empty?(worktrees) do
        Mix.shell().info("Available: #{Enum.join(worktrees, ", ")}")
      end
    end
  end

  defp remove_worktree(name, force) do
    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    unless File.dir?(worktree_path) do
      Mix.shell().error("Error: Worktree #{worktree_path} does not exist")
      list_available_worktrees()
      exit({:shutdown, 1})
    end

    # Get info before removal
    branch = get_worktree_branch(worktree_path)
    port = get_worktree_port(worktree_path)
    database = Tak.database_for(name)

    # Stop services on port
    if port do
      Mix.shell().info("Stopping services on port #{port}...")
      Tak.kill_port(port)
    end

    # Remove worktree
    Mix.shell().info("Removing worktree...")

    remove_result =
      if force do
        System.cmd("git", ["worktree", "remove", "--force", worktree_path], stderr_to_stdout: true)
      else
        System.cmd("git", ["worktree", "remove", worktree_path], stderr_to_stdout: true)
      end

    case remove_result do
      {_, 0} ->
        :ok

      {output, _} ->
        unless force do
          Mix.shell().error("Failed to remove worktree (uncommitted changes?)")
          Mix.shell().error(output)
          Mix.shell().info("Use --force to force removal")
          exit({:shutdown, 1})
        end
    end

    # Clean up any orphaned files
    File.rm_rf(worktree_path)
    System.cmd("git", ["worktree", "prune"], stderr_to_stdout: true)

    # Delete branch
    if branch && branch != "unknown" do
      Mix.shell().info("Deleting branch #{branch}...")

      if force do
        System.cmd("git", ["branch", "-D", branch], stderr_to_stdout: true)
      else
        case System.cmd("git", ["branch", "-d", branch], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {_, _} -> Mix.shell().info("Branch not deleted (unmerged changes or doesn't exist)")
        end
      end
    end

    # Drop database
    Mix.shell().info("Dropping database #{database}...")

    case System.cmd("dropdb", [database], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, _} -> Mix.shell().info("Database not dropped (may not exist)")
    end

    # Success output
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree removed successfully!"]))
    Mix.shell().info("")
    Mix.shell().info("  Name:     #{name}")
    if branch && branch != "unknown", do: Mix.shell().info("  Branch:   #{branch}")
    Mix.shell().info("  Database: #{database}")
  end

  defp get_worktree_branch(worktree_path) do
    abs_path = Path.expand(worktree_path)

    case System.cmd("git", ["worktree", "list", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n\n")
        |> Enum.find_value(fn block ->
          if String.contains?(block, "worktree #{abs_path}") do
            block
            |> String.split("\n")
            |> Enum.find_value(fn line ->
              case String.split(line, "branch refs/heads/") do
                [_, branch] -> branch
                _ -> nil
              end
            end)
          end
        end)

      _ ->
        nil
    end
  end

  defp get_worktree_port(worktree_path) do
    mise_path = Path.join(worktree_path, "mise.local.toml")
    env_path = Path.join(worktree_path, ".env")

    cond do
      File.exists?(mise_path) ->
        mise_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/PORT\s*=\s*"?(\d+)"?/, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      File.exists?(env_path) ->
        env_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/^PORT=(\d+)/m, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      true ->
        nil
    end
  end
end
