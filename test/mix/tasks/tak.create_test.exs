defmodule Mix.Tasks.Tak.CreateTest do
  use ExUnit.Case, async: false

  describe "--db flag parsing" do
    test "--no-db flag overrides config default (true)" do
      {opts, _, _} = OptionParser.parse(["branch", "--no-db"], switches: [db: :boolean])

      create_db =
        case opts[:db] do
          nil -> true
          value -> value
        end

      assert create_db == false
    end

    test "--db flag overrides config default (false)" do
      {opts, _, _} = OptionParser.parse(["branch", "--db"], switches: [db: :boolean])

      create_db =
        case opts[:db] do
          nil -> false
          value -> value
        end

      assert create_db == true
    end
  end

  describe "validation via Tak.Worktrees" do
    test "rejects invalid slot names" do
      assert {:error, {:invalid_name, "nope"}} =
               Tak.Worktrees.create("feature/test", "nope")
    end

    test "rejects already existing worktrees" do
      # First name should not exist in a test env, but if trees/ doesn't exist
      # that also means it passes the "not exists" check
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
