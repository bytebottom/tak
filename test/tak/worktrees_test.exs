defmodule Tak.TestSystem do
  def configure(handler, executables \\ %{}) do
    Process.put({__MODULE__, :handler}, handler)
    Process.put({__MODULE__, :executables}, executables)
    Process.put({__MODULE__, :history}, [])
  end

  def history do
    Process.get({__MODULE__, :history}, []) |> Enum.reverse()
  end

  def cmd(command, args, opts \\ []) do
    Process.put({__MODULE__, :history}, [
      {command, args, opts} | Process.get({__MODULE__, :history}, [])
    ])

    Process.get({__MODULE__, :handler}).(command, args, opts)
  end

  def find_executable(name) do
    Map.get(Process.get({__MODULE__, :executables}, %{}), name)
  end
end

defmodule Tak.WorktreesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "tak_worktrees_test_#{System.unique_integer([:positive])}")

    trees_dir = Path.join(tmp_dir, "trees")
    File.mkdir_p!(trees_dir)

    previous = %{
      trees_dir: Application.get_env(:tak, :trees_dir),
      names: Application.get_env(:tak, :names),
      base_port: Application.get_env(:tak, :base_port),
      system_mod: Application.get_env(:tak, :system_mod)
    }

    Application.put_env(:tak, :trees_dir, trees_dir)
    Application.put_env(:tak, :names, ["armstrong", "hickey"])
    Application.put_env(:tak, :base_port, 4000)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tak, key)
        {key, value} -> Application.put_env(:tak, key, value)
      end)
    end)

    {:ok, tmp_dir: tmp_dir, trees_dir: trees_dir}
  end

  describe "list/0" do
    test "returns {main, worktrees} tuple of typed status entries" do
      {main, worktrees} = Tak.Worktrees.list()

      assert %Tak.WorktreeStatus{} = main
      assert %Tak.Worktree{name: "main", port: port} = main.worktree
      assert is_integer(port)
      assert main.status in [:running, :stopped]
      assert is_list(worktrees)
    end

    test "entries use a consistent typed shape" do
      {main, worktrees} = Tak.Worktrees.list()

      for entry <- [main | worktrees] do
        assert %Tak.WorktreeStatus{} = entry
        assert %Tak.Worktree{} = entry.worktree
        assert entry.status in [:running, :stopped, :unknown]
      end
    end

    test "main status is inferred from the nested worktree name" do
      {main, worktrees} = Tak.Worktrees.list()

      assert main.worktree.name == "main"
      assert Enum.all?(worktrees, fn entry -> entry.worktree.name != "main" end)
    end

    test "prefers metadata over legacy config when both exist", %{trees_dir: trees_dir} do
      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(Path.join(worktree_path, "config"))

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/from-metadata",
        port: 4550,
        path: worktree_path,
        database: "tak_dev_armstrong",
        database_managed?: true
      })

      File.write!(Path.join(worktree_path, "config/dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :tak, TakWeb.Endpoint,
        http: [port: 4999]

      config :tak, Tak.Repo,
        database: "wrong_db"
      """)

      {_main, [entry]} = Tak.Worktrees.list()

      assert entry.worktree.branch == "feature/from-metadata"
      assert entry.worktree.port == 4550
      assert entry.worktree.database == "tak_dev_armstrong"
    end

    test "falls back to legacy config when metadata is absent", %{trees_dir: trees_dir} do
      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(Path.join(worktree_path, "config"))

      File.write!(Path.join(worktree_path, "config/dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :tak, TakWeb.Endpoint,
        http: [port: 4770]

      config :tak, Tak.Repo,
        database: "tak_dev_armstrong"
      """)

      {_main, [entry]} = Tak.Worktrees.list()

      assert entry.worktree.name == "armstrong"
      assert entry.worktree.port == 4770
      assert entry.worktree.database == "tak_dev_armstrong"
      assert entry.worktree.database_managed? == true
    end
  end

  describe "doctor/0" do
    test "returns structured results" do
      {passed, failed, results} = Tak.Worktrees.doctor()
      assert is_integer(passed)
      assert is_integer(failed)
      assert is_list(results)

      for result <- results do
        case result do
          {:ok, msg} -> assert is_binary(msg)
          {:error, msg, reason} -> assert is_binary(msg) and is_binary(reason)
          {:warn, msg, reason} -> assert is_binary(msg) and is_binary(reason)
        end
      end
    end

    test "git check passes" do
      {_, _, results} = Tak.Worktrees.doctor()
      assert {:ok, "git available"} in results
    end
  end

  describe "create/3 validation" do
    test "rejects invalid names" do
      assert {:error, {:invalid_name, "nope"}} = Tak.Worktrees.create("branch", "nope")
    end

    test "rejects already-existing worktrees", %{trees_dir: trees_dir} do
      name = List.first(Tak.names())
      path = Path.join(trees_dir, name)
      File.mkdir_p!(path)

      assert {:error, {:already_exists, ^name}} =
               Tak.Worktrees.create("feature/test", name)
    end
  end

  describe "create/3" do
    test "writes metadata only after successful bootstrap", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], opts ->
          assert opts[:cd] == Path.join(trees_dir, "armstrong")
          {"", 0}

        "mix", ["ecto.setup"], opts ->
          assert opts[:cd] == Path.join(trees_dir, "armstrong")
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, worktree} = Tak.Worktrees.create("feature/test", "armstrong", create_db: true)
      assert File.exists?(Path.join(worktree.path, ".tak"))

      metadata = Tak.Metadata.read(worktree.path)
      assert metadata.name == "armstrong"
      assert metadata.database == "tak_dev_armstrong"
      assert metadata.database_managed? == true
    end

    test "cleans up the worktree when bootstrap fails", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "git", ["worktree", "remove", "--force", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"", 0}

        "git", ["branch", "-D", _branch], _opts ->
          {"", 0}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        "mix", ["ecto.setup"], _opts ->
          {"ecto failed", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:error, {:bootstrap_failed, "mix ecto.setup", "ecto failed"}} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: true)

      refute File.exists?(Path.join([trees_dir, "armstrong", ".tak"]))
      refute File.dir?(Path.join(trees_dir, "armstrong"))
    end

    test "returns cleanup_failed when automatic cleanup cannot complete", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "git", ["worktree", "remove", "--force", _path], _opts ->
          {"cleanup failed", 1}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        "mix", ["ecto.setup"], _opts ->
          {"ecto failed", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:error, {:bootstrap_failed, "mix ecto.setup", "ecto failed", :cleanup_failed}} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: true)

      refute File.exists?(Path.join([trees_dir, "armstrong", ".tak"]))
      assert File.dir?(Path.join(trees_dir, "armstrong"))
    end

    test "logs a warning when the assigned port is already in use" do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      {:ok, socket} = :gen_tcp.listen(4010, reuseaddr: true)

      log =
        capture_log(fn ->
          assert {:ok, _worktree} =
                   Tak.Worktrees.create("feature/test", "armstrong", create_db: false)
        end)

      assert log =~ "Tak worktree port 4010 is already in use"
      :gen_tcp.close(socket)
    end
  end

  describe "remove/2" do
    test "keeps the database when requested", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(worktree_path)

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/test",
        port: 4010,
        path: worktree_path,
        database: "tak_dev_armstrong",
        database_managed?: true
      })

      Tak.TestSystem.configure(fn
        "lsof", _args, _opts ->
          {"", 1}

        "git", ["worktree", "remove", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"", 0}

        "git", ["branch", "-d", _branch], _opts ->
          {"", 0}

        "dropdb", _args, _opts ->
          flunk("dropdb should not run when keep_db is true")

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, %Tak.RemoveResult{} = result} =
               Tak.Worktrees.remove("armstrong", keep_db: true)

      assert result.worktree.database == "tak_dev_armstrong"
      assert result.database_cleanup == :kept
      refute File.dir?(worktree_path)
      refute Enum.any?(Tak.TestSystem.history(), fn {command, _, _} -> command == "dropdb" end)
    end

    test "succeeds even when prune fails after worktree removal", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(worktree_path)

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/test",
        port: 4010,
        path: worktree_path,
        database: nil,
        database_managed?: false
      })

      Tak.TestSystem.configure(fn
        "lsof", _args, _opts ->
          {"", 1}

        "git", ["worktree", "remove", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["branch", "-d", _branch], _opts ->
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"prune warning", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      log =
        capture_log(fn ->
          assert {:ok, %Tak.RemoveResult{} = result} = Tak.Worktrees.remove("armstrong")
          assert result.worktree.name == "armstrong"
          assert result.database_cleanup == nil
        end)

      assert log =~ "Tak prune failed after worktree removal"
      refute File.dir?(worktree_path)
    end
  end
end
