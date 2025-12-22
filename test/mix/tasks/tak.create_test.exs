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

    test "no flag uses config default" do
      {opts, _, _} = OptionParser.parse(["branch"], switches: [db: :boolean])

      create_db =
        case opts[:db] do
          nil -> Tak.create_database?()
          value -> value
        end

      assert create_db == Tak.create_database?()
    end

    test "no flag respects config override" do
      Application.put_env(:tak, :create_database, false)

      {opts, _, _} = OptionParser.parse(["branch"], switches: [db: :boolean])

      create_db =
        case opts[:db] do
          nil -> Tak.create_database?()
          value -> value
        end

      assert create_db == false
    after
      Application.delete_env(:tak, :create_database)
    end
  end
end
