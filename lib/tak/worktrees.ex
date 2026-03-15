defmodule Tak.Worktrees do
  @moduledoc """
  Public runtime API for Tak worktree lifecycle operations.

  The supported surface is intentionally small:

    * `create/3` creates a worktree and returns `%Tak.Worktree{}` data
    * `list/0` reports the main repo and known worktrees with runtime status
    * `remove/2` removes a worktree and returns `%Tak.RemoveResult{}` data
    * `doctor/0` returns structured environment checks for CLI rendering

  Tak uses three public data shapes:

    * `Tak.Worktree`, stable worktree identity and configuration
    * `Tak.WorktreeStatus`, transient runtime status layered on top of a worktree
    * `Tak.RemoveResult`, removal outcome layered on top of a worktree
  """

  require Logger

  @doc """
  Creates a worktree. Returns `{:ok, %Tak.Worktree{}}` or `{:error, reason}`.

  When `name` is `nil`, the first available slot is picked automatically.

  The core API does not raise for expected git or mix command failures. Those
  return tagged errors instead:

    * `{:git_failed, command, output}`
    * `{:bootstrap_failed, command, output}`
    * `{:bootstrap_failed, command, output, :cleanup_failed}`

  ## Options

    * `:create_db` - whether to create the database (default: from config)
  """
  def create(branch, name, opts \\ []) do
    create_db = Keyword.get(opts, :create_db, Tak.create_database?())

    with {:ok, name} <- resolve_name(name),
         :ok <- validate_not_exists(name) do
      trees_dir = Tak.trees_dir()
      worktree_path = Path.join(trees_dir, name)
      branch_exists? = Tak.Git.branch_exists?(branch)

      worktree = %Tak.Worktree{
        name: name,
        branch: branch,
        port: Tak.port_for(name),
        path: worktree_path,
        database: if(create_db, do: Tak.database_for(name)),
        database_managed?: create_db
      }

      maybe_warn_port_in_use(worktree.port)
      File.mkdir_p!(trees_dir)

      with {:ok, _output} <- add_git_worktree(branch, worktree_path, branch_exists?),
           :ok <- copy_env_file(worktree_path),
           :ok <- write_dev_local_config(worktree.path, worktree.name, worktree.port, create_db),
           :ok <- maybe_write_mise_config(worktree.path, worktree.port),
           :ok <- bootstrap_worktree(worktree.path, create_db) do
        Tak.Metadata.write!(worktree)
        {:ok, worktree}
      else
        {:error, {:git_failed, _command, _output} = reason} ->
          {:error, reason}

        {:error, {:bootstrap_failed, _command, _output} = reason} ->
          {:error, cleanup_after_bootstrap_failure(worktree, branch_exists?, reason)}
      end
    end
  end

  @doc """
  Lists the main repository and all known worktrees.

  Returns `{main, worktrees}` where `main` is a `%Tak.WorktreeStatus{}` for the
  current repository and `worktrees` is a list of `%Tak.WorktreeStatus{}`
  values for entries found in `Tak.trees_dir/0`.

  Status is `:running`, `:stopped`, or `:unknown`.
  """
  def list do
    trees_dir = Tak.trees_dir()
    base_port = Tak.base_port()

    {main_status, main_pid} = check_port(base_port)

    main = %Tak.WorktreeStatus{
      worktree: %Tak.Worktree{
        name: "main",
        branch: Tak.Git.current_branch(),
        port: base_port,
        path: Path.expand("."),
        database: nil,
        database_managed?: false
      },
      status: main_status,
      pid: main_pid
    }

    worktrees =
      if File.dir?(trees_dir) do
        trees_dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(trees_dir, &1)))
        |> Enum.map(fn name ->
          worktree_path = Path.join(trees_dir, name)
          load_worktree_status(name, worktree_path)
        end)
      else
        []
      end

    {main, worktrees}
  end

  @doc """
  Removes a worktree. Returns `{:ok, %Tak.RemoveResult{}}` or `{:error, reason}`.

  ## Options

    * `:force` - force removal even with uncommitted changes (default: false)
    * `:keep_db` - keep the database instead of dropping it (default: false)
  """
  def remove(name, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    keep_db = Keyword.get(opts, :keep_db, false)
    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    if not File.dir?(worktree_path) do
      {:error, {:not_found, name}}
    else
      status = load_worktree_status(name, worktree_path)
      worktree = status.worktree

      if worktree.port, do: Tak.Port.kill(worktree.port)

      with :ok <- remove_git_worktree(worktree_path, force),
           :ok <- maybe_delete_branch(worktree.branch, force) do
        best_effort_prune_worktrees()
        database_cleanup = maybe_cleanup_database(worktree, keep_db)
        {:ok, %Tak.RemoveResult{worktree: worktree, database_cleanup: database_cleanup}}
      end
    end
  end

  @doc """
  Runs doctor checks. Returns `{passed, failed, results}` where results is a
  list of `{:ok | :error | :warn, message}` tuples.
  """
  def doctor do
    results = [
      check_dev_local_import(),
      check_gitignore("dev.local.exs", "config/dev.local.exs", required: true),
      check_gitignore("mise.local.toml", "mise.local.toml",
        required: false,
        note: "only needed if using mise"
      ),
      check_gitignore(Tak.trees_dir(), "#{Tak.trees_dir()}/", required: true),
      check_executable("git", required: true),
      check_executable("dropdb", required: false, note: "needed for tak.remove")
    ]

    passed = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _, _}, &1))

    {passed, failed, results}
  end

  defp maybe_warn_port_in_use(nil), do: :ok

  defp maybe_warn_port_in_use(port) do
    if Tak.Port.in_use?(port) do
      Logger.warning("Tak worktree port #{port} is already in use")
    end

    :ok
  end

  defp pick_available_name do
    trees_dir = Tak.trees_dir()

    available =
      Enum.filter(Tak.names(), fn name ->
        not File.dir?(Path.join(trees_dir, name))
      end)

    case available do
      [] -> {:error, :no_slots}
      [first | _] -> {:ok, first}
    end
  end

  defp add_git_worktree(branch, worktree_path, true) do
    run_git(["worktree", "add", worktree_path, branch], :git_failed)
  end

  defp add_git_worktree(branch, worktree_path, false) do
    run_git(["worktree", "add", "-b", branch, worktree_path], :git_failed)
  end

  defp cleanup_after_bootstrap_failure(
         worktree,
         branch_exists?,
         {:bootstrap_failed, command, output}
       ) do
    cleanup_result =
      with :ok <- remove_git_worktree(worktree.path, true),
           :ok <- prune_worktrees(),
           :ok <- maybe_delete_created_branch(worktree.branch, branch_exists?) do
        :ok
      end

    case cleanup_result do
      :ok ->
        {:bootstrap_failed, command, output}

      _ ->
        {:bootstrap_failed, command, output, :cleanup_failed}
    end
  end

  defp remove_git_worktree(worktree_path, force) do
    args =
      if force,
        do: ["worktree", "remove", "--force", worktree_path],
        else: ["worktree", "remove", worktree_path]

    case run_git(args, :worktree_remove_failed) do
      {:ok, _output} ->
        File.rm_rf(worktree_path)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prune_worktrees do
    case run_git(["worktree", "prune"], :git_prune_failed) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp best_effort_prune_worktrees do
    case prune_worktrees() do
      :ok ->
        :ok

      {:error, {_tag, command, output}} ->
        Logger.warning("Tak prune failed after worktree removal: #{command}\n#{output}")
        :ok
    end
  end

  defp maybe_delete_branch(nil, _force), do: :ok

  defp maybe_delete_branch(branch, force) do
    delete_flag = if force, do: "-D", else: "-d"

    case run_git(["branch", delete_flag, branch], :branch_delete_failed) do
      {:ok, _output} -> :ok
      {:error, _reason} when not force -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_delete_created_branch(_branch, true), do: :ok
  defp maybe_delete_created_branch(nil, false), do: :ok

  defp maybe_delete_created_branch(branch, false) do
    case run_git(["branch", "-D", branch], :branch_delete_failed) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_cleanup_database(%Tak.Worktree{database_managed?: false}, _keep_db), do: nil
  defp maybe_cleanup_database(%Tak.Worktree{database: nil}, _keep_db), do: nil
  defp maybe_cleanup_database(%Tak.Worktree{}, true), do: :kept

  defp maybe_cleanup_database(%Tak.Worktree{database: database}, false) do
    case Tak.System.cmd("dropdb", [database], stderr_to_stdout: true) do
      {_, 0} -> :dropped
      _ -> :failed
    end
  end

  defp copy_env_file(worktree_path) do
    if File.exists?(".env") do
      File.cp!(".env", Path.join(worktree_path, ".env"))
    end

    :ok
  end

  defp bootstrap_worktree(path, create_db) do
    with {:ok, _output} <- run_mix(path, ["deps.get"]),
         :ok <- maybe_setup_database(path, create_db) do
      :ok
    end
  end

  defp maybe_setup_database(_path, false), do: :ok

  defp maybe_setup_database(path, true) do
    case run_mix(path, ["ecto.setup"]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_git(args, tag) do
    case Tak.Git.run(args) do
      {:ok, output} -> {:ok, output}
      {:error, output} -> {:error, {tag, Enum.join(["git" | args], " "), output}}
    end
  end

  defp run_mix(path, args) do
    command = Enum.join(["mix" | args], " ")

    case Tak.System.cmd("mix", args, cd: path, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}]) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, {:bootstrap_failed, command, output}}
    end
  end

  defp resolve_name(nil), do: pick_available_name()

  defp resolve_name(name) do
    if name in Tak.names(), do: {:ok, name}, else: {:error, {:invalid_name, name}}
  end

  defp validate_not_exists(name) do
    path = Path.join(Tak.trees_dir(), name)
    if File.dir?(path), do: {:error, {:already_exists, name}}, else: :ok
  end

  defp load_worktree_status(name, worktree_path) do
    worktree =
      case Tak.Metadata.read(worktree_path) do
        %Tak.Worktree{} = wt ->
          %Tak.Worktree{wt | branch: wt.branch || Tak.Git.worktree_branch(worktree_path)}

        nil ->
          branch = Tak.Git.worktree_branch(worktree_path)
          port = Tak.Config.get_port(worktree_path)
          has_db = Tak.Config.has_database?(worktree_path)

          %Tak.Worktree{
            name: name,
            branch: branch,
            port: port,
            path: worktree_path,
            database: if(has_db, do: Tak.database_for(name)),
            database_managed?: has_db
          }
      end

    {status, pid} = check_port(worktree.port)

    %Tak.WorktreeStatus{
      worktree: worktree,
      status: status,
      pid: pid
    }
  end

  defp check_port(nil), do: {:unknown, nil}

  defp check_port(port) do
    if Tak.Port.in_use?(port) do
      {:running, Tak.Port.pid(port)}
    else
      {:stopped, nil}
    end
  end

  defp write_dev_local_config(worktree_path, name, port, create_db) do
    app_name = Tak.app_name()
    endpoint = inspect(Tak.endpoint())
    repo = inspect(Tak.repo())

    config_dir = Path.join(worktree_path, "config")
    File.mkdir_p!(config_dir)
    dest_path = Path.join(config_dir, "dev.local.exs")
    source_path = "config/dev.local.exs"

    db_config =
      if create_db do
        database = Tak.database_for(name)

        """

        config :#{app_name}, #{repo},
          database: "#{database}"
        """
      else
        ""
      end

    tak_config =
      """

      # Tak worktree config (#{name})
      # These values override any earlier config above
      config :#{app_name}, #{endpoint},
        http: [port: #{port}]
      """ <> db_config

    if File.exists?(source_path) do
      existing = File.read!(source_path)
      File.write!(dest_path, existing <> tak_config)
    else
      File.write!(dest_path, "import Config" <> tak_config)
    end

    :ok
  end

  defp maybe_write_mise_config(worktree_path, port) do
    if Tak.mise_available?() do
      do_write_mise_config(worktree_path, port)
    else
      :ok
    end
  end

  defp do_write_mise_config(worktree_path, port) do
    mise_config = """
    [env]
    PORT = "#{port}"
    """

    mise_path = Path.join(worktree_path, "mise.local.toml")
    File.write!(mise_path, mise_config)
    Tak.System.cmd("mise", ["trust", mise_path], stderr_to_stdout: true)
    :ok
  end

  # --- Doctor checks ---

  defp check_dev_local_import do
    config_path = "config/config.exs"

    cond do
      not File.exists?(config_path) ->
        {:error, "config/config.exs imports local overrides", "File not found"}

      true ->
        content = File.read!(config_path)

        if Regex.match?(~r/import_config.*\.local\.exs/, content) do
          {:ok, "config/config.exs imports local overrides"}
        else
          {:error, "config/config.exs imports local overrides", "Missing import"}
        end
    end
  end

  defp check_gitignore(pattern, display, opts) do
    required = Keyword.get(opts, :required, true)
    note = Keyword.get(opts, :note)
    gitignore_path = ".gitignore"

    cond do
      not File.exists?(gitignore_path) ->
        if required,
          do: {:error, "#{display} in .gitignore", ".gitignore not found"},
          else: {:warn, "#{display} in .gitignore", note}

      true ->
        content = File.read!(gitignore_path)
        lines = String.split(content, "\n")

        found =
          Enum.any?(lines, fn line ->
            line = String.trim(line)

            cond do
              String.starts_with?(line, "#") -> false
              line == "" -> false
              String.contains?(line, pattern) -> true
              true -> false
            end
          end)

        cond do
          found -> {:ok, "#{display} in .gitignore"}
          required -> {:error, "#{display} in .gitignore", "Not ignored"}
          true -> {:warn, "#{display} in .gitignore", note}
        end
    end
  end

  defp check_executable(name, opts) do
    required = Keyword.get(opts, :required, true)
    note = Keyword.get(opts, :note)

    if Tak.System.find_executable(name) do
      {:ok, "#{name} available"}
    else
      if required,
        do: {:error, "#{name} available", "Not found"},
        else: {:warn, "#{name} available", "Not found (#{note})"}
    end
  end
end
