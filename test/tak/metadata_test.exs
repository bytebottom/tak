defmodule Tak.MetadataTest do
  use ExUnit.Case, async: true

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "tak_metadata_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  test "write! and read round-trip a worktree", %{tmp_dir: tmp_dir} do
    worktree = %Tak.Worktree{
      name: "armstrong",
      branch: "feature/login",
      port: 4010,
      path: tmp_dir,
      database: "myapp_dev_armstrong",
      database_managed?: true
    }

    Tak.Metadata.write!(worktree)

    result = Tak.Metadata.read(tmp_dir)
    assert result.name == "armstrong"
    assert result.branch == "feature/login"
    assert result.port == 4010
    assert result.path == tmp_dir
    assert result.database == "myapp_dev_armstrong"
    assert result.database_managed? == true
  end

  test "write! and read round-trip without database", %{tmp_dir: tmp_dir} do
    worktree = %Tak.Worktree{
      name: "hickey",
      branch: "fix/bug",
      port: 4020,
      path: tmp_dir,
      database: nil,
      database_managed?: false
    }

    Tak.Metadata.write!(worktree)

    result = Tak.Metadata.read(tmp_dir)
    assert result.name == "hickey"
    assert result.database == nil
    assert result.database_managed? == false
  end

  test "read returns nil when no metadata file", %{tmp_dir: tmp_dir} do
    assert Tak.Metadata.read(tmp_dir) == nil
  end

  test "read returns nil for corrupt metadata", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, ".tak"), "not valid elixir {{{}}")
    assert Tak.Metadata.read(tmp_dir) == nil
  end

  test "metadata file is human-readable", %{tmp_dir: tmp_dir} do
    worktree = %Tak.Worktree{
      name: "armstrong",
      branch: "main",
      port: 4010,
      path: tmp_dir,
      database: "app_dev_armstrong",
      database_managed?: true
    }

    Tak.Metadata.write!(worktree)

    content = File.read!(Path.join(tmp_dir, ".tak"))
    assert content =~ "name:"
    assert content =~ "armstrong"
    assert content =~ "port: 4010"
  end
end
