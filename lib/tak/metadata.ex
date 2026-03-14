defmodule Tak.Metadata do
  @moduledoc false

  @filename ".tak"

  @doc """
  Writes worktree metadata as an Elixir term file.
  """
  def write!(%Tak.Worktree{} = worktree) do
    data = %{
      name: worktree.name,
      branch: worktree.branch,
      port: worktree.port,
      database: worktree.database,
      database_managed?: worktree.database_managed?
    }

    content = "#{inspect(data, pretty: true, limit: :infinity)}\n"
    File.write!(path(worktree.path), content)
  end

  @doc """
  Reads worktree metadata from the `.tak` file, returning a `Tak.Worktree` struct
  or `nil` if the file doesn't exist or can't be parsed.
  """
  def read(worktree_path) do
    file = path(worktree_path)

    if File.exists?(file) do
      with {:ok, content} <- File.read(file),
           {%{} = data, _} <- safe_eval(content) do
        %Tak.Worktree{
          name: data[:name],
          branch: data[:branch],
          port: data[:port],
          path: worktree_path,
          database: data[:database],
          database_managed?: data[:database_managed?] || false
        }
      else
        _ -> nil
      end
    end
  end

  defp safe_eval(content) do
    Code.eval_string(content)
  rescue
    _ -> nil
  end

  defp path(worktree_path), do: Path.join(worktree_path, @filename)
end
