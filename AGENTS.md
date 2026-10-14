# kraken-feed: agent guide

## Purpose

Read-only public market data from Kraken as a `Market_data.Feed.t`: spot trades, best bid and
offer and the L2 book over websocket v2, and futures funding over websocket v1. No API keys and
no order entry. The same raw frames can be normalized again by `rebuild-norm`, so a recorded
day rebuilds without the network.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | Library `kraken-feed`: `Config`, `Wire`, `Symbols`, `Local_book`, `Checksum`, `Normalizer`, `Live_feed`, `Raw_normalizer` |
| `bin/` | The `kraken-feed` CLI: `feed` and `rebuild-norm` |
| `test/` | Expect and property tests; `test/fixtures/raw/kraken` is a recorded minute set |
| `bench/` | Per-frame time and allocation benchmark |
| `docs/` | `kraken-ws-spec.md`, notes on the Kraken websocket frames |
| `.github/` | CI workflow |

## Build, test, docs

Run from this repository, inside the workspace (sibling checkouts and a root `dune-workspace`):

    opam exec --switch 5.2.0+ox -- dune build --root .. @kraken-feed/all
    opam exec --switch 5.2.0+ox -- dune build --root .. @kraken-feed/runtest

Several agents building at once need their own build directory:
`DUNE_BUILD_DIR=_build-kraken-feed` in front of the same commands.

Standalone, outside the workspace: add the organization's opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`),
install the published dependencies, then run `dune build` here.

## Conventions

- Format this repository only: `dune build --root .. @kraken-feed/fmt --auto-promote`. Never
  `dune fmt` at the workspace root; it rewrites every repository.
- Every module has an `.mli`; every public value has an odoc comment.
- Tests are expect tests (`ppx_expect`) and unit tests. Promote expect output with
  `dune promote` after reading the diff.
- Prices and sizes stay as the venue sent them until the checksum is verified.
- Allocation and time figures in the README come from an arm64 Mac. Word counts differ on
  amd64, so a pin in `bench/` or `test/test_allocation.ml` needs a tolerance that holds on both,
  with a comment saying why.

## Dependencies

- Depends on sibling repositories `market-data`, `venue-net`, `fixed-decimal` and `exchange-core`.
- Used by `market-recorder` (raw paths escape `/` in spot symbols as `_`) and by the tests of
  `market-replay`.
- CI pins follow the `pins:` list in `.github/workflows/ci.yml`; a new sibling dependency must be
  added to that list in dependency order.

## CI

`.github/workflows/ci.yml` runs the `infra` ox-setup action (a cached opam switch built from
the pins), then `dune build` and `dune test`. The `obj-magic` job calls the reusable workflow
in `winterchill-trading/infra`. A concurrency group cancels superseded runs.
To check a run, use `gh run list --limit 1` and at most one `gh run watch <id> --exit-status`.
Never poll in a loop.

## Pitfalls

- Spot symbols are `BTC/USD` (Kraken does not say `XBT` there); futures use `PF_XBTUSD`.
- The book checksum is CRC32 over the exact decimal strings. Parse numbers with `Yojson.Raw`
  and trim the book to the subscribed depth before checksumming, or every check fails.
- Spot has no sequence numbers. A checksum mismatch is the only resync signal: drop the book,
  resubscribe the symbol, wait for the new snapshot.
- Under the ox switch, inline tests need `(flags (:standard -source-tree-root .))` in the test
  `dune` stanza, or every partition fails with "No such file".
- `Time_ns` sexps print in the local zone, so expect output with timestamps differs between a Mac
  and CI. Print UTC or nanoseconds.
- Under `open! Async`, `print_endline` in a `Command.basic` body never flushes; use `Command.async`.

## Where to read more

- `README.md` (library, CLI, fixtures, gaps, recorded costs)
- `docs/kraken-ws-spec.md`
- `../specs/repos/kraken-feed.md` (design, pins, known gaps)
- `../oxcaml-claude-skills/AGENTS.md` (workspace guide) and `../oxcaml-claude-skills/GOTCHAS.md`
- Skills in `../oxcaml-claude-skills/skills/`: `async-http-websocket`, `janestreet-ocaml-style`,
  `oxcaml-performance`

## Never do

- Run `opam install`, `upgrade` or `pin` that would change `ocaml-variants`, `core`, `base`,
  `async` or `ppx_jane` on the shared `5.2.0+ox` switch.
- Publish, tag or release.
- Commit credentials. This repository reads public endpoints only.
- Poll CI in a loop.
