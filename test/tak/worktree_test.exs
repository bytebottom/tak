defmodule Tak.WorktreeTest do
  use ExUnit.Case, async: true

  test "struct enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(Tak.Worktree, %{})
    end
  end

  test "struct has sensible defaults" do
    wt = %Tak.Worktree{name: "armstrong", port: 4010, path: "trees/armstrong"}
    assert wt.branch == nil
    assert wt.database == nil
    assert wt.database_managed? == false
  end
end
