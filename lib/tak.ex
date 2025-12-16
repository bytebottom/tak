defmodule Tak do
  @moduledoc """
  Git worktree management for Elixir/Phoenix development.

  Tak (Dutch for "branch") helps you manage multiple git worktrees,
  each with isolated ports and databases for parallel development.

  ## Available Tasks

    * `mix tak.create` - Create a new worktree with isolated config
    * `mix tak.list` - List all worktrees and their status
    * `mix tak.remove` - Remove a worktree and clean up resources
    * `mix tak.doctor` - Check if project is configured correctly

  ## Configuration

  Configure Tak in your `config/config.exs`:

      config :tak,
        names: ~w(armstrong hickey siebel mccarthy),
        base_port: 4000,
        trees_dir: "trees"

  ## How It Works

  Each worktree gets:
    * `config/dev.local.exs` with isolated port and database
    * `mise.local.toml` with PORT env var (if mise is installed)

  Ports are assigned based on name index: armstrong=4010, hickey=4020, etc.
  """

  @default_names ~w(armstrong hickey siebel mccarthy)
  @default_base_port 4000
  @default_trees_dir "trees"

  @doc """
  Returns the list of available worktree names.
  """
  def names do
    Application.get_env(:tak, :names, @default_names)
  end

  @doc """
  Returns the base port number.
  """
  def base_port do
    Application.get_env(:tak, :base_port, @default_base_port)
  end

  @doc """
  Returns the directory where worktrees are stored.
  """
  def trees_dir do
    Application.get_env(:tak, :trees_dir, @default_trees_dir)
  end

  @doc """
  Returns the app name from the current Mix project.
  """
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc """
  Returns the module name (camelized) from the app name.
  """
  def module_name do
    app_name()
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc """
  Calculates the port for a given worktree name.
  """
  def port_for(name) do
    case Enum.find_index(names(), &(&1 == name)) do
      nil -> nil
      index -> base_port() + (index + 1) * 10
    end
  end

  @doc """
  Returns the database name for a given worktree.
  """
  def database_for(name) do
    "#{app_name()}_dev_#{name}"
  end

  @doc """
  Checks if a port is in use.
  """
  def port_in_use?(port) do
    case System.cmd("lsof", ["-i", ":#{port}"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Gets the PID using a given port, if any.
  """
  def pid_on_port(port) do
    case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.trim() |> String.split("\n") |> List.first()

      _ ->
        nil
    end
  end

  @doc """
  Kills processes on a given port.
  """
  def kill_port(port) do
    case pid_on_port(port) do
      nil -> :ok
      pid -> System.cmd("kill", ["-9", pid], stderr_to_stdout: true)
    end
  end

  @doc """
  Checks if mise is available on the system.
  """
  def mise_available? do
    case System.cmd("which", ["mise"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Gets the port configured for a worktree by reading its config files.

  Checks in order:
  1. `config/dev.local.exs` - Elixir config
  2. `mise.local.toml` - mise env (legacy)
  3. `.env` - dotenv file (legacy)
  """
  def get_worktree_port(worktree_path) do
    dev_local_path = Path.join([worktree_path, "config", "dev.local.exs"])
    mise_path = Path.join(worktree_path, "mise.local.toml")
    env_path = Path.join(worktree_path, ".env")

    cond do
      File.exists?(dev_local_path) ->
        dev_local_path
        |> File.read!()
        |> then(fn content ->
          # Match port: anywhere within http: [...] block
          case Regex.run(~r/http:\s*\[[^\]]*port:\s*(\d+)/, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      # Fallback for legacy mise.local.toml
      File.exists?(mise_path) ->
        mise_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/PORT\s*=\s*"?(\d+)"?/, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      # Fallback for .env
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

  @doc """
  Gets the branch name for a worktree from git.
  """
  def get_worktree_branch(worktree_path) do
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
end
