defmodule Tak.Worktree do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          branch: String.t() | nil,
          port: non_neg_integer(),
          path: String.t(),
          database: String.t() | nil,
          database_managed?: boolean()
        }

  @enforce_keys [:name, :port, :path]
  defstruct [:name, :branch, :port, :path, :database, database_managed?: false]
end
