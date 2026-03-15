defmodule Mix.Tasks.Tak.CreateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defmodule TestSystem do
    def configure(handler) do
      Process.put({__MODULE__, :handler}, handler)
    end

    def cmd(command, args, opts \\ []) do
      Process.get({__MODULE__, :handler}).(command, args, opts)
    end

    def find_executable(_name), do: nil
  end

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "tak_create_task_test_#{System.unique_integer([:positive])}")

    trees_dir = Path.join(tmp_dir, "trees")
    File.mkdir_p!(trees_dir)

    previous = %{
      trees_dir: Application.get_env(:tak, :trees_dir),
      names: Application.get_env(:tak, :names),
      system_mod: Application.get_env(:tak, :system_mod)
    }

    Application.put_env(:tak, :trees_dir, trees_dir)
    Application.put_env(:tak, :names, ["armstrong", "hickey"])

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tak, key)
        {key, value} -> Application.put_env(:tak, key, value)
      end)
    end)

    {:ok, trees_dir: trees_dir}
  end

  describe "validation via Tak.Worktrees" do
    test "rejects invalid slot names" do
      assert {:error, {:invalid_name, "nope"}} =
               Tak.Worktrees.create("feature/test", "nope")
    end

    test "rejects already existing worktrees", %{trees_dir: trees_dir} do
      name = List.first(Tak.names())
      path = Path.join(trees_dir, name)
      File.mkdir_p!(path)

      assert {:error, {:already_exists, ^name}} =
               Tak.Worktrees.create("feature/test", name)
    end
  end

  describe "run/1" do
    test "shows the auto-picked name before creation starts", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, TestSystem)
      File.mkdir_p!(Path.join(trees_dir, "armstrong"))

      TestSystem.configure(fn
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

      output =
        capture_io(fn ->
          Mix.Tasks.Tak.Create.run(["feature/test"])
        end)

      assert output =~ "Creating worktree 'hickey' for branch 'feature/test'..."
      assert output =~ "Worktree created successfully!"
      assert output =~ "hickey"
    end
  end
end
