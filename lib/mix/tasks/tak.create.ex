defmodule Mix.Tasks.Tak.Create do
  @shortdoc "Create a new git worktree with isolated config"
  @moduledoc """
  Creates a git worktree with isolated configuration for Elixir/Phoenix development.

      $ mix tak.create <branch-name> [name]

  This will:

    * Create a git worktree in `trees/<name>/`
    * Set up a unique port via `mise.local.toml`
    * Create `config/dev.local.exs` with isolated database
    * Copy dependencies and build artifacts from main repo
    * Run `mix deps.get` and `mix ecto.setup`

  ## Arguments

    * `branch-name` - The git branch to create/checkout (required)
    * `name` - The worktree name (optional, auto-assigned from available names)

  ## Available Names

  By default: armstrong, hickey, siebel, mccarthy

  Configure in your `config/config.exs`:

      config :tak, names: ~w(custom names here)

  ## Examples

      $ mix tak.create feature/login
      $ mix tak.create feature/login armstrong

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        Mix.shell().error("Usage: mix tak.create <branch-name> [name]")
        Mix.shell().info("Available names: #{Enum.join(Tak.names(), ", ")}")
        exit({:shutdown, 1})

      [branch | rest] ->
        name = List.first(rest) || pick_available_name()
        create_worktree(branch, name)
    end
  end

  defp pick_available_name do
    trees_dir = Tak.trees_dir()

    available =
      Enum.find(Tak.names(), fn name ->
        not File.dir?(Path.join(trees_dir, name))
      end)

    case available do
      nil ->
        Mix.shell().error("Error: All worktree names are in use (#{Enum.join(Tak.names(), ", ")})")
        exit({:shutdown, 1})

      name ->
        name
    end
  end

  defp create_worktree(branch, name) do
    unless name in Tak.names() do
      Mix.shell().error("Error: Invalid name '#{name}'. Choose from: #{Enum.join(Tak.names(), ", ")}")
      exit({:shutdown, 1})
    end

    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    if File.dir?(worktree_path) do
      Mix.shell().error("Error: Worktree #{worktree_path} already exists")
      exit({:shutdown, 1})
    end

    port = Tak.port_for(name)

    if Tak.port_in_use?(port) do
      Mix.shell().info("Warning: Port #{port} is already in use")
    end

    # Create trees directory
    File.mkdir_p!(trees_dir)

    # Create worktree
    Mix.shell().info("Creating worktree '#{name}' for branch '#{branch}'...")

    if branch_exists?(branch) do
      git!(["worktree", "add", worktree_path, branch])
    else
      git!(["worktree", "add", "-b", branch, worktree_path])
    end

    # Copy .env if it exists
    if File.exists?(".env") do
      File.cp!(".env", Path.join(worktree_path, ".env"))
    end

    # Create mise.local.toml for port
    mise_config = """
    [env]
    PORT = "#{port}"
    """

    File.write!(Path.join(worktree_path, "mise.local.toml"), mise_config)
    System.cmd("mise", ["trust", Path.join(worktree_path, "mise.local.toml")], stderr_to_stdout: true)

    # Create dev.local.exs for database
    app_name = Tak.app_name()
    module_name = Tak.module_name()
    database = Tak.database_for(name)

    dev_local = """
    import Config

    config :#{app_name}, #{module_name}.Repo,
      database: "#{database}"
    """

    config_dir = Path.join(worktree_path, "config")
    File.mkdir_p!(config_dir)
    File.write!(Path.join(config_dir, "dev.local.exs"), dev_local)

    # Copy dependencies and caches
    Mix.shell().info("Copying dependencies...")

    for dir <- ["deps", "_build", ".expert"] do
      if File.dir?(dir) do
        File.cp_r!(dir, Path.join(worktree_path, dir))
      end
    end

    # Run setup in worktree
    Mix.shell().info("Installing dependencies...")
    mix_in_worktree!(worktree_path, ["deps.get"])

    Mix.shell().info("Setting up database...")
    mix_in_worktree!(worktree_path, ["ecto.setup"])

    # Success output
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree created successfully!"]))
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, name, :reset, " ", :faint, "(#{branch})"]))
    Mix.shell().info("  Port:     #{port}")
    Mix.shell().info("  Database: #{database}")
    Mix.shell().info("  Location: #{worktree_path}")
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:faint, "To start the server:"]))
    Mix.shell().info(IO.ANSI.format([:bright, "  cd #{worktree_path} && iex -S mix phx.server"]))
    Mix.shell().info("")
  end

  defp branch_exists?(branch) do
    case System.cmd("git", ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("git #{Enum.join(args, " ")} failed:\n#{output}")
    end
  end

  defp mix_in_worktree!(path, args) do
    case System.cmd("mix", args, cd: path, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}]) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("mix #{Enum.join(args, " ")} failed in #{path}:\n#{output}")
    end
  end
end
