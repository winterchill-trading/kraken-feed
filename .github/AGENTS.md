# .github: kraken-feed CI

`workflows/ci.yml` builds and tests the repository on Linux with the `infra` ox-setup action.

Rules:

- The `pins:` list names the sibling repositories this library builds against, in dependency
  order, as listed in `../specs/repos/kraken-feed.md`. A missing pin fails with "unknown package".
- The `obj-magic` job calls the reusable workflow in `winterchill-trading/infra`. Do not copy its
  steps into this file.
- To check a run: `gh run list --limit 1`, then at most one `gh run watch <id> --exit-status`.
