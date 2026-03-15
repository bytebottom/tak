defmodule Tak.WorktreeStatus do
  @moduledoc """
  Runtime status for a worktree.

  `%Tak.WorktreeStatus{}` pairs a `%Tak.Worktree{}` with observation-only data
  such as running state and PID. This keeps stable worktree identity separate
  from transient process state.
  """

  @type status :: :running | :stopped | :unknown

  @type t :: %__MODULE__{
          worktree: Tak.Worktree.t(),
          status: status(),
          pid: String.t() | nil
        }

  @enforce_keys [:worktree, :status]
  defstruct [:worktree, :status, :pid]
end
