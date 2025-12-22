# Changelog

## 0.2.0

- Add `--db` / `--no-db` flags to `mix tak.create` to control database creation
- Add `create_database` config option (default: `true`)
- Skip database drop on `mix tak.remove` when database wasn't created by tak

## 0.1.0

- Initial release
- `mix tak.create` - Create git worktrees with isolated ports and databases
- `mix tak.list` - List all worktrees with status
- `mix tak.remove` - Remove worktrees and clean up resources
- `mix tak.doctor` - Verify project configuration
- Automatic port assignment based on worktree name
- Automatic database naming (`<app>_dev_<name>`)
- mise integration for PORT environment variable
- Configurable worktree names, base port, and trees directory
