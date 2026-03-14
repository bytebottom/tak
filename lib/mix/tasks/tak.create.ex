defmodule Mix.Tasks.Tak.Create do
  @shortdoc "Create a new git worktree with isolated config"
  @moduledoc """
  Creates a git worktree with an isolated port and database for parallel development.

      $ mix tak.create <branch-name> [name]

  The worktree lands in `trees/<name>/` and gets its own `config/dev.local.exs`
  with a dedicated port and (optionally) a dedicated database. If
  [mise](https://mise.jdx.dev) is installed, a `mise.local.toml` is also written
  so the `PORT` env var stays consistent across shells.

  After setup, the task runs `mix deps.get` and, when creating a database,
  `mix ecto.setup` inside the new worktree.

  If a `.env` file exists in the project root, it is copied into the worktree.

  ## Arguments

    * `branch-name` — the git branch to create or check out (required)
    * `name` — the worktree slot name (optional; first available is picked when omitted)

  ## Options

    * `--db` — create the database, overriding the `create_database` config value
    * `--no-db` — skip database creation, overriding the `create_database` config value

  ## Examples

      $ mix tak.create feature/login
      $ mix tak.create feature/login armstrong
      $ mix tak.create feature/login --no-db

  Run `mix tak.doctor` first if this is a new project to verify your config is ready.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: [db: :boolean])

    create_db =
      case opts[:db] do
        nil -> Tak.create_database?()
        value -> value
      end

    case positional do
      [] ->
        Mix.shell().error("Usage: mix tak.create <branch-name> [name] [--db | --no-db]")
        Mix.shell().info("Available names: #{Enum.join(Tak.names(), ", ")}")
        exit({:shutdown, 1})

      [branch | rest] ->
        name = List.first(rest)

        Mix.shell().info("Creating worktree for branch '#{branch}'...")

        case Tak.Worktrees.create(branch, name, create_db: create_db) do
          {:ok, worktree} ->
            render_success(worktree)

          {:error, :no_slots} ->
            Mix.shell().error("Error: All worktree names are in use (#{Enum.join(Tak.names(), ", ")})")
            exit({:shutdown, 1})

          {:error, {:invalid_name, n}} ->
            Mix.shell().error("Error: Invalid name '#{n}'. Choose from: #{Enum.join(Tak.names(), ", ")}")
            exit({:shutdown, 1})

          {:error, {:already_exists, n}} ->
            Mix.shell().error("Error: Worktree #{Path.join(Tak.trees_dir(), n)} already exists")
            exit({:shutdown, 1})
        end
    end
  end

  defp render_success(worktree) do
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree created successfully!"]))
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, worktree.name, :reset, " ", :faint, "(#{worktree.branch})"]))
    Mix.shell().info("  Port:     #{worktree.port}")
    if worktree.database, do: Mix.shell().info("  Database: #{worktree.database}")
    Mix.shell().info("  Location: #{worktree.path}")
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:faint, "To start the server:"]))
    Mix.shell().info(IO.ANSI.format([:bright, "  cd #{worktree.path} && iex -S mix phx.server"]))
    Mix.shell().info("")
  end
end
