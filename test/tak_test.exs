defmodule TakTest do
  use ExUnit.Case, async: true

  describe "names/0" do
    test "returns default names" do
      assert Tak.names() == ~w(armstrong hickey mccarthy lovelace kay valim)
    end
  end

  describe "base_port/0" do
    test "returns default base port" do
      assert Tak.base_port() == 4000
    end
  end

  describe "trees_dir/0" do
    test "returns default trees directory" do
      assert Tak.trees_dir() == "trees"
    end
  end

  describe "create_database?/0" do
    test "returns true by default" do
      assert Tak.create_database?() == true
    end

    test "respects config override" do
      Application.put_env(:tak, :create_database, false)
      assert Tak.create_database?() == false
    after
      Application.delete_env(:tak, :create_database)
    end
  end

  describe "port_for/1" do
    test "calculates port based on name index" do
      assert Tak.port_for("armstrong") == 4010
      assert Tak.port_for("hickey") == 4020
      assert Tak.port_for("mccarthy") == 4030
      assert Tak.port_for("lovelace") == 4040
      assert Tak.port_for("kay") == 4050
      assert Tak.port_for("valim") == 4060
    end

    test "returns nil for unknown name" do
      assert Tak.port_for("unknown") == nil
    end
  end

  describe "database_for/1" do
    test "generates database name with app and worktree name" do
      assert Tak.database_for("armstrong") == "tak_dev_armstrong"
    end
  end

  describe "module_name/0" do
    test "camelizes the app name" do
      assert Tak.module_name() == "Tak"
    end
  end

  describe "mise_available?/0" do
    test "returns a boolean" do
      result = Tak.mise_available?()
      assert is_boolean(result)
    end
  end

  describe "endpoint/0" do
    test "infers from app name by default" do
      assert Tak.endpoint() == TakWeb.Endpoint
    end

    test "respects config override" do
      Application.put_env(:tak, :endpoint, MyCustomWeb.Endpoint)
      assert Tak.endpoint() == MyCustomWeb.Endpoint
    after
      Application.delete_env(:tak, :endpoint)
    end
  end

  describe "repo/0" do
    test "infers from app name by default" do
      assert Tak.repo() == Tak.Repo
    end

    test "respects config override" do
      Application.put_env(:tak, :repo, MyCustom.Repo)
      assert Tak.repo() == MyCustom.Repo
    after
      Application.delete_env(:tak, :repo)
    end
  end
end
