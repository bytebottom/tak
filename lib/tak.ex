defmodule Tak do
  @moduledoc """
  Resolves names, ports, and database identifiers for git worktrees.

  Tak (Dutch for "branch") manages multiple git worktrees in parallel, each
  with an isolated port and database. This module is the central source of
  truth for configuration: it reads application config, derives per-worktree
  values, and exposes them to the Mix tasks and helper modules.

  ## Mix tasks

    * `mix tak.create` — create a new worktree with isolated config
    * `mix tak.list` — list all worktrees and their status
    * `mix tak.remove` — remove a worktree and clean up resources
    * `mix tak.doctor` — check if the project is configured correctly

  ## Configuration

  Set options in `config/config.exs`:

      config :tak,
        names: ~w(armstrong hickey mccarthy lovelace kay valim),
        base_port: 4000,
        trees_dir: "trees",
        create_database: true,
        endpoint: MyAppWeb.Endpoint,
        repo: MyApp.Repo

  ### Options

    * `:names` — worktree slot names, one per available worktree
      (default: `armstrong hickey mccarthy lovelace kay valim`)
    * `:base_port` — base port; each worktree gets `base_port + (index + 1) * 10`
      (default: `4000`)
    * `:trees_dir` — directory where worktrees are checked out (default: `"trees"`)
    * `:create_database` — run `mix ecto.setup` when creating a worktree
      (default: `true`); override per invocation with `--db` or `--no-db`
    * `:endpoint` — the Phoenix endpoint module (default: inferred from app name)
    * `:repo` — the Ecto repo module (default: inferred from app name)

  ## Port assignment

  Ports are derived from the name's position in the `:names` list:

      base_port + (index + 1) * 10

  With the defaults, `armstrong` gets `4010`, `hickey` gets `4020`,
  `mccarthy` gets `4030`, and so on.

  ## Per-worktree files

  `mix tak.create` writes these files inside each worktree:

    * `.tak` — Tak-owned metadata (name, branch, port, database)
    * `config/dev.local.exs` — sets the HTTP port and (optionally) the database name
    * `mise.local.toml` — sets the `PORT` env var (only when `mise` is installed)
  """

  @default_names ~w(armstrong hickey mccarthy lovelace kay valim)
  @default_base_port 4000
  @default_trees_dir "trees"
  @default_create_database true

  @doc """
  Returns the configured endpoint module.

  Defaults to `MyAppWeb.Endpoint` based on the app name convention.
  Override with `config :tak, endpoint: MyCustomWeb.Endpoint`.
  """
  def endpoint do
    case Application.get_env(:tak, :endpoint) do
      nil -> Module.concat([module_name() <> "Web", "Endpoint"])
      mod -> mod
    end
  end

  @doc """
  Returns the configured repo module.

  Defaults to `MyApp.Repo` based on the app name convention.
  Override with `config :tak, repo: MyCustom.Repo`.
  """
  def repo do
    case Application.get_env(:tak, :repo) do
      nil -> Module.concat([module_name(), "Repo"])
      mod -> mod
    end
  end

  @doc """
  Returns the configured list of worktree slot names.

  ## Example

      iex> is_list(Tak.names())
      true
  """
  def names do
    Application.get_env(:tak, :names, @default_names)
  end

  @doc """
  Returns the configured base port number.

  ## Example

      iex> is_integer(Tak.base_port())
      true
  """
  def base_port do
    Application.get_env(:tak, :base_port, @default_base_port)
  end

  @doc """
  Returns the configured directory where worktrees are stored.

  ## Example

      iex> is_binary(Tak.trees_dir())
      true
  """
  def trees_dir do
    Application.get_env(:tak, :trees_dir, @default_trees_dir)
  end

  @doc """
  Returns whether `mix tak.create` should run `mix ecto.setup` by default.

  Override per invocation with `--db` or `--no-db`.

  ## Example

      iex> is_boolean(Tak.create_database?())
      true
  """
  def create_database? do
    Application.get_env(:tak, :create_database, @default_create_database)
  end

  @doc """
  Returns the OTP application name from the current Mix project.

  Delegates to `Mix.Project.config/0`, so it reflects whichever project is
  currently loaded. In a worktree, that is the worktree's project.
  """
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc false
  def module_name do
    app_name()
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc """
  Returns the port assigned to a worktree name, or `nil` if the name is not
  in the configured name list.

  The port is `base_port() + (index + 1) * 10`, where `index` is the name's
  zero-based position in `names()`. With default config, `"armstrong"` (index
  0) gets port `4010`, `"hickey"` (index 1) gets `4020`, and so on.

  ## Examples

      iex> Tak.port_for("armstrong")
      4010

      iex> Tak.port_for("hickey")
      4020

      iex> Tak.port_for("unknown")
      nil
  """
  def port_for(name) do
    case Enum.find_index(names(), &(&1 == name)) do
      nil -> nil
      index -> base_port() + (index + 1) * 10
    end
  end

  @doc """
  Returns the PostgreSQL database name for a worktree.

  The name follows the pattern `<app>_dev_<worktree>`. For example, with
  `app_name()` of `:my_app` and a worktree named `"armstrong"`, this returns
  `"my_app_dev_armstrong"`.

  ## Example

      iex> is_binary(Tak.database_for("armstrong"))
      true
  """
  def database_for(name) do
    "#{app_name()}_dev_#{name}"
  end

  @doc """
  Returns `true` if the `mise` executable is on `PATH`.

  When `true`, `mix tak.create` also writes a `mise.local.toml` that sets
  the `PORT` env var, ensuring the port is consistent whether the server is
  started through `mise` or directly.
  """
  def mise_available? do
    System.find_executable("mise") != nil
  end
end
