# bench: kraken-feed benchmark

`main.ml` and `live.ml` build the `core_bench` executables. The recorded minute frames of
`test/fixtures/raw/kraken` are embedded at build time by the rule in `dune`, so the benchmark
needs no network. It times and counts allocation per frame for each stream (`trades`, `bbo`,
`l2`, `funding`), JSON decoding included. The numbers in the README come from an arm64 Mac in
the dev profile.

Rules:

- Do not compare these numbers with another machine's; quote the machine with any new figure.
- Minor-word pins are tolerant because amd64 CI counts differ. Keep the comment beside any pin
  you change.
- Benchmarks do not run in CI. A change that moves a number should update the README table in
  the same commit.
- Add a fixture by adding its `cat` line to the `dune` rule, not by copying frames into source.
