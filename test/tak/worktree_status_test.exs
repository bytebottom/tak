defmodule Tak.WorktreeStatusTest do
  use ExUnit.Case, async: true

  test "struct enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(Tak.WorktreeStatus, %{})
    end
  end

  test "struct keeps stable worktree data separate from runtime status" do
    worktree = %Tak.Worktree{name: "armstrong", port: 4010, path: "trees/armstrong"}

    status = %Tak.WorktreeStatus{worktree: worktree, status: :stopped}

    assert status.worktree == worktree
    assert status.status == :stopped
    assert status.pid == nil
  end
end
