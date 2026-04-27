# Contributing to x1-sentinel

Thanks for considering a contribution.

## Reporting bugs

Please include:

1. Output of `x1-sentinel --list-metrics 60` (so we can see your build's metric names)
2. The dashboard screenshot showing the issue
3. Your validator: `tachyon-validator --version` (or equivalent)
4. OS: `lsb_release -a`
5. Contents of `/dev/shm/sentinel.*/debug.log` if any

## Adding support for a new validator build

The parser is structured around metric names. To add a build:

1. Run `x1-sentinel --list-metrics 90` on a host running that build.
2. Compare the output to the case statements in `lib/parser.sh` (or the inline parser in `x1-sentinel`).
3. Add new cases for whatever names differ. Send a PR with the field samples in the commit message.

## Code style

- POSIX-leaning bash, but we use bash 4+ features (associative arrays, `[[`, `<<<`)
- Defensive defaults: every variable read should have `:-` fallback
- No `set -u` in collector subshells (see lessons in commit history)
- Errors go to `$STATE_DIR/debug.log`, not stderr (would corrupt TUI)
- Comment metric-extraction logic with the *actual sample line* it parses

## Testing

Before submitting:

```bash
bash -n install.sh         # syntax check
bash -n x1-sentinel
bash -n lib/*.sh
shellcheck install.sh x1-sentinel lib/*.sh   # if you have shellcheck
```

Run on at least one real validator before requesting review. Confirm:

- Self-check passes
- All panels populate within 30 seconds
- Risk score stays at LOW on a healthy validator

## License

By contributing you agree your contribution is licensed under MIT.
