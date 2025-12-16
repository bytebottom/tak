defmodule Tak do
  @moduledoc """
  Git worktree management for Elixir/Phoenix development.

  Tak (Dutch for "branch") helps you manage multiple git worktrees,
  each with isolated ports and databases for parallel development.

  ## Available Tasks

    * `mix tak.create` - Create a new worktree
    * `mix tak.list` - List all worktrees and their status
    * `mix tak.remove` - Remove a worktree and clean up resources

  ## Configuration

  Configure Tak in your `config/config.exs`:

      config :tak,
        names: ~w(armstrong hickey siebel mccarthy),
        base_port: 4000,
        trees_dir: "trees"

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
end
