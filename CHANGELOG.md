# Changelog

## 0.4.2

- Show the auto-picked worktree name before `mix tak.create` begins work
- Remove redundant `main?` from `%Tak.WorktreeStatus{}` and infer main status from `worktree.name`

## 0.4.1

- Document `Tak.Worktrees`, `Tak.Worktree`, `Tak.WorktreeStatus`, and `Tak.RemoveResult` as the supported runtime API
- Make `Tak.Worktrees.list/0` return typed `%Tak.WorktreeStatus{}` entries instead of ad hoc maps
- Make `Tak.Worktrees.create/3` return tagged errors for git/bootstrap command failures instead of raising for expected subprocess failures
- Write `.tak` metadata only after successful bootstrap and perform best-effort cleanup when bootstrap fails
- Restore the create-time port collision warning
- Preserve database identity on remove and report cleanup outcome separately (`:dropped`, `:kept`, `:failed`)
- Treat `git worktree prune` as best-effort during remove, so prune failure after deletion does not turn a successful removal into an error
- Harden `.tak` parsing with required-key and value-shape validation
- Add a small system-command boundary so core workflow tests can exercise command-heavy paths without shelling out for real
- Expand test coverage for metadata-first listing, legacy fallback, create failure cleanup, keep-db removal, and port collision warnings

## 0.4.0

- **Breaking:** Internal git, config, and port helpers are now hidden from generated docs
- Extract all workflow orchestration from Mix tasks into `Tak.Worktrees` core module
- Mix tasks are now thin wrappers: parse args, call core, render output
- Add `%Tak.Worktree{}` struct as the canonical data shape
- Add `.tak` metadata file per worktree (replaces config scraping as primary source of truth)
- Add `:endpoint` and `:repo` config options for non-standard Phoenix naming
- Add `--keep-db` flag to `mix tak.remove`
- Slot selection is now deterministic (first available, not random)
- Replace the `"unknown"` branch sentinel with `nil` in branch detection
- Tighten doctor `import_config` check to use regex instead of substring match
- Legacy config scraping preserved as fallback for pre-metadata worktrees
- Expanded test coverage (34 -> 51 tests)

## 0.3.0

- **Breaking:** Extract internal port, config, and git helpers from monolithic `Tak`
- Add confirmation prompt to `mix tak.remove` (skip with `--yes`)
- Use `:gen_tcp` for port detection instead of `lsof` (removes system dependency for create/list)
- Graceful process shutdown: send SIGTERM before SIGKILL when stopping worktree services
- Replace `System.cmd("which", ...)` with `System.find_executable/1` for portability
- Expanded test coverage (23 -> 34 tests)

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
