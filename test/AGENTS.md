# test: kraken-feed tests

Expect tests and property tests for the library, plus a helper set that replays the fixtures.

- `test/fixtures/raw/kraken` is a recorded mainnet minute set (`BTC/USD`, `PF_XBTUSD`). Tests read
  it as it is; do not regenerate or edit it. Add a new recording as a new directory.
- `fake_ws.ml` is a scripted websocket server for the `Live_feed` tests.
- `test_reconnect_fake_clock.ml` steps reconnects on a synthetic clock. Do not add real sleeps.
- `test_allocation.ml` pins minor words per frame; read the tolerance comment before changing it.
- Promote expect output only after reading the diff: `dune promote`.
- Run from the workspace: `opam exec --switch 5.2.0+ox -- dune build --root .. @kraken-feed/runtest`.
