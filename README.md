# Tak

Git worktree management for Elixir/Phoenix development.

**Tak** (Dutch for "branch") helps you manage multiple git worktrees, each with isolated ports and databases for parallel development.

## Requirements

- **Elixir/Phoenix** project with Ecto
- **macOS or Linux** (uses `lsof` for port detection)
- **PostgreSQL** (for database management)
- **Git** (for worktree management)
- **mise** (optional, for PORT environment variable)

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
$ mix tak.create feature/login armstrong  # specify name
```

This will:
- Create a git worktree in `trees/<name>/`
- Create `config/dev.local.exs` with isolated port and database
- If [mise](https://mise.jdx.dev/) is installed, create `mise.local.toml` with PORT env var
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

### Check configuration

```bash
$ mix tak.doctor
```

Verifies your project is configured correctly for tak (gitignore, dev.local.exs import, etc.).

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

## Setup

Run `mix tak.doctor` to check your project is configured correctly. You'll need:

1. `config/dev.exs` must import `dev.local.exs`:
   ```elixir
   # At the end of config/dev.exs
   import_config "dev.local.exs"
   ```

2. Add to `.gitignore`:
   ```
   /config/dev.local.exs
   /mise.local.toml
   /trees/
   ```

## How it works

Each worktree gets a `config/dev.local.exs` with:
- **Unique port**: Assigned based on name index (armstrong=4010, hickey=4020, etc.)
- **Isolated database**: `<app>_dev_<name>` (e.g., `myapp_dev_armstrong`)

If [mise](https://mise.jdx.dev/) is installed, a `mise.local.toml` is also created with the PORT env var to override any inherited environment.

## License

MIT
