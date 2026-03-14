defmodule Tak.WorktreesTest do
  use ExUnit.Case, async: false

  describe "list/0" do
    test "returns {main, worktrees} tuple" do
      {main, worktrees} = Tak.Worktrees.list()
      assert main.name == "main"
      assert is_integer(main.port)
      assert main.status in [:running, :stopped]
      assert is_list(worktrees)
    end

    test "entries have consistent map shape" do
      {main, worktrees} = Tak.Worktrees.list()

      for entry <- [main | worktrees] do
        assert Map.has_key?(entry, :name)
        assert Map.has_key?(entry, :branch)
        assert Map.has_key?(entry, :port)
        assert Map.has_key?(entry, :status)
        assert Map.has_key?(entry, :pid)
        assert Map.has_key?(entry, :database)
        assert Map.has_key?(entry, :database_managed?)
        assert entry.status in [:running, :stopped, :unknown]
      end
    end

    test "main entry does not have main? key" do
      {main, _} = Tak.Worktrees.list()
      refute Map.has_key?(main, :main?)
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

    test "rejects already-existing worktrees" do
      trees_dir = Tak.trees_dir()
      name = List.first(Tak.names())
      path = Path.join(trees_dir, name)

      if File.dir?(path) do
        assert {:error, {:already_exists, ^name}} =
                 Tak.Worktrees.create("feature/test", name)
      end
    end
  end
end
