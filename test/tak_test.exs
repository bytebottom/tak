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
      # This depends on Mix.Project.config()[:app] which is :tak in test
      assert Tak.database_for("armstrong") == "tak_dev_armstrong"
    end
  end

  describe "module_name/0" do
    test "camelizes the app name" do
      # :tak -> "Tak"
      assert Tak.module_name() == "Tak"
    end
  end

describe "has_database_config?/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "tak_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      {:ok, tmp_dir: tmp_dir}
    end

    test "returns true when tak added database config", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]

      config :myapp, Myapp.Repo,
        database: "myapp_dev_armstrong"
      """)

      assert Tak.has_database_config?(tmp_dir) == true
    end

    test "returns false when tak config exists but no database", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]
      """)

      assert Tak.has_database_config?(tmp_dir) == false
    end

    test "returns false when database config exists but not from tak", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      config :myapp, Myapp.Repo,
        database: "myapp_dev"
      """)

      assert Tak.has_database_config?(tmp_dir) == false
    end

    test "returns false when no config file exists", %{tmp_dir: tmp_dir} do
      assert Tak.has_database_config?(tmp_dir) == false
    end
  end

  describe "get_worktree_port/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "tak_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      {:ok, tmp_dir: tmp_dir}
    end

    test "reads port from dev.local.exs", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]
      """)

      assert Tak.get_worktree_port(tmp_dir) == 4010
    end

    test "reads port from dev.local.exs with multiple http options", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [ip: {127, 0, 0, 1}, port: 4020]
      """)

      assert Tak.get_worktree_port(tmp_dir) == 4020
    end

    test "reads port from multiline http config", %{tmp_dir: tmp_dir} do
      config_dir = Path.join(tmp_dir, "config")
      File.mkdir_p!(config_dir)

      File.write!(Path.join(config_dir, "dev.local.exs"), """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [
          ip: {127, 0, 0, 1},
          port: 4050
        ]
      """)

      assert Tak.get_worktree_port(tmp_dir) == 4050
    end

    test "falls back to mise.local.toml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mise.local.toml"), """
      [env]
      PORT = "4030"
      """)

      assert Tak.get_worktree_port(tmp_dir) == 4030
    end

    test "falls back to .env", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".env"), """
      PORT=4040
      """)

      assert Tak.get_worktree_port(tmp_dir) == 4040
    end

    test "returns nil when no config found", %{tmp_dir: tmp_dir} do
      assert Tak.get_worktree_port(tmp_dir) == nil
    end
  end
end
