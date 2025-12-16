# Tak

Git worktree management for Elixir/Phoenix development.

**Tak** (Dutch for "branch") helps you manage multiple git worktrees, each with isolated ports and databases for parallel development.

## Installation

Add `tak` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tak, "~> 0.1.0", only: :dev}
  ]
end
```

## Usage

### Create a worktree

```bash
$ mix tak.create feature/login
```

This will:
- Create a git worktree in `trees/<name>/`
- Set up a unique port via `mise.local.toml`
- Create `config/dev.local.exs` with isolated database
- Copy dependencies and build artifacts from main repo
- Run `mix deps.get` and `mix ecto.setup`

### List worktrees

```bash
$ mix tak.list
```

Shows all worktrees with their branch, port, database, and running status.

### Remove a worktree

```bash
$ mix tak.remove armstrong
$ mix tak.remove armstrong --force
```

This will stop services, remove the worktree, delete the branch, and drop the database.

## Configuration

Configure Tak in your `config/config.exs`:

```elixir
config :tak,
  names: ~w(armstrong hickey siebel mccarthy),
  base_port: 4000,
  trees_dir: "trees"
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `names` | `~w(armstrong hickey siebel mccarthy)` | Available worktree slot names |
| `base_port` | `4000` | Base port (worktrees use 4010, 4020, etc.) |
| `trees_dir` | `"trees"` | Directory to store worktrees |

## How it works

Each worktree gets:
- **Unique port**: Assigned based on name index (armstrong=4010, hickey=4020, etc.)
- **Isolated database**: `<app>_dev_<name>` (e.g., `myapp_dev_armstrong`)
- **Local config**: `mise.local.toml` for port, `config/dev.local.exs` for database

## License

MIT
