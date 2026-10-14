# lib: kraken-feed library

Library `kraken-feed` (module `Kraken_feed`). Entry points:

- `Live_feed`: one socket per stream, reconnect and resync, `stats`, and `?time_source` for the
  clock that stamps `recv_ts` and drives pings and backoff.
- `Normalizer`: pure frame-to-event conversion with checksummed books.
- `Raw_normalizer`: the `Market_data.Normalizer.S` used by `rebuild-norm`.
- `Wire`, `Symbols`, `Local_book`, `Checksum`, `Config`: frame shapes, names, book state, CRC32,
  endpoints.

Rules:

- `Wire` keeps numbers as sent (`Yojson.Raw`). Converting to float first breaks the CRC32 check.
- A checksum mismatch drops the book and resubscribes that symbol. Do not patch the book in place.
- Levels beyond the subscribed depth are removed locally and reported as zero-size levels.
- Each `.mli` documents every public value; keep the `.mli` and `.ml` in step.
- Keep this directory free of I/O beyond the sockets in `Live_feed`; tests use a fake clock.

Read `../specs/repos/kraken-feed.md` for the sequencing rules before changing `Local_book`.
