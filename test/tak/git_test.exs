defmodule Tak.GitTest do
  use ExUnit.Case, async: false

  describe "current_branch/0" do
    test "returns a branch name or nil" do
      branch = Tak.Git.current_branch()
      assert is_binary(branch) or is_nil(branch)

      if branch do
        assert String.length(branch) > 0
      end
    end
  end

  describe "branch_exists?/1" do
    test "returns true for main branch" do
      assert Tak.Git.branch_exists?("main")
    end

    test "returns false for nonexistent branch" do
      refute Tak.Git.branch_exists?("this-branch-definitely-does-not-exist-#{:rand.uniform(100_000)}")
    end
  end

  describe "worktree_branch/1" do
    test "returns nil for a path that is not a worktree" do
      assert Tak.Git.worktree_branch("/tmp/nonexistent_#{:rand.uniform(100_000)}") == nil
    end
  end
end
