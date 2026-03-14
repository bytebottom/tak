defmodule Mix.Tasks.Tak.Remove do
  @shortdoc "Remove a git worktree and clean up resources"
  @moduledoc """
  Removes a git worktree and releases its port, branch, and database.

      $ mix tak.remove <name> [--force] [--yes] [--keep-db]

  Steps, in order:

  1. Kill any process using the worktree's port (SIGTERM, then SIGKILL after 2s).
  2. Remove the git worktree directory.
  3. Delete the git branch with `git branch -d` (safe: skips if the branch is
     unmerged). Pass `--force` to use `git branch -D` instead.
  4. Drop the database with `dropdb`, but only if tak created it. Pass `--keep-db`
     to skip database removal.

  Without `--yes`, the task prints what it will delete and asks for confirmation.

  ## Arguments

    * `name` — the worktree slot name to remove (required)

  ## Options

    * `--force` — remove even with uncommitted changes; force-delete the branch
    * `--yes` — skip the confirmation prompt
    * `--keep-db` — keep the database instead of dropping it

  ## Examples

      $ mix tak.remove armstrong
      $ mix tak.remove armstrong --force
      $ mix tak.remove armstrong --yes
      $ mix tak.remove armstrong --keep-db

  > #### Warning {: .warning}
  >
  > `--force` deletes the branch even if it has unmerged commits. Make sure
  > your work is pushed or merged before using it.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args, strict: [force: :boolean, yes: :boolean, keep_db: :boolean])

    force = Keyword.get(opts, :force, false)
    skip_confirm = Keyword.get(opts, :yes, false)
    keep_db = Keyword.get(opts, :keep_db, false)

    case args do
      [] ->
        Mix.shell().error("Usage: mix tak.remove <name> [--force] [--yes] [--keep-db]")
        list_available_worktrees()
        exit({:shutdown, 1})

      [name | _] ->
        trees_dir = Tak.trees_dir()
        worktree_path = Path.join(trees_dir, name)

        unless File.dir?(worktree_path) do
          Mix.shell().error("Error: Worktree #{worktree_path} does not exist")
          list_available_worktrees()
          exit({:shutdown, 1})
        end

        unless skip_confirm do
          Mix.shell().info("This will remove:")
          Mix.shell().info("  Worktree: #{worktree_path}")

          unless Mix.shell().yes?("Continue?") do
            Mix.shell().info("Aborted.")
            exit(:normal)
          end
        end

        Mix.shell().info("Removing worktree '#{name}'...")

        case Tak.Worktrees.remove(name, force: force, keep_db: keep_db) do
          {:ok, worktree} ->
            render_success(worktree)

          {:error, {:not_found, n}} ->
            Mix.shell().error("Error: Worktree #{Path.join(trees_dir, n)} does not exist")
            exit({:shutdown, 1})

          {:error, {:worktree_remove_failed, output}} ->
            Mix.shell().error("Failed to remove worktree (uncommitted changes?)")
            Mix.shell().error(output)
            Mix.shell().info("Use --force to force removal")
            exit({:shutdown, 1})
        end
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

  defp render_success(worktree) do
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree removed successfully!"]))
    Mix.shell().info("")
    Mix.shell().info("  Name:     #{worktree.name}")
    if worktree.branch, do: Mix.shell().info("  Branch:   #{worktree.branch}")
    if worktree.database, do: Mix.shell().info("  Database: #{worktree.database}")
  end
end
