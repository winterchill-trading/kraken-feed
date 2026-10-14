# docs: kraken-feed protocol notes

`kraken-ws-spec.md` records the Kraken websocket frames the library parses: subscribe
acknowledgements, the `trade`, `ticker` (BBO) and `book` channels on spot v2, and the futures v1
`ticker` used for funding.

Rules:

- Write what the venue sends, with the frame shape as an example. Do not copy wording from
  Kraken's documentation pages.
- When a parser changes, update the matching section here in the same commit.
- Design decisions belong in `../../specs/repos/kraken-feed.md`, not in this directory.
