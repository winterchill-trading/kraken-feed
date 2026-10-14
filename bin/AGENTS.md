# bin: kraken-feed CLI

`kraken_feed_cli.ml` defines the `kraken-feed` command tree:

- `feed`: `-symbol`, `-streams`, `-count`, `-l2-depth`, `-raw`, `-spot-url`, `-futures-url`.
- `rebuild-norm`: `-data-dir`, `-out`, `-date YYYY-MM-DD`. Rebuilds one day of normalized logs
  from recorded raw minutes through `Raw_normalizer`.

Rules:

- Keep the flag names stable; `market-recorder` and the scripts call them.
- Config errors print with `eprint_s` and exit; do not raise, so the message stays short.
- Anything that runs Async uses `Command.async`, not `Command.basic`.
