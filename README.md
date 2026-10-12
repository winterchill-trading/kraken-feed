# kraken-feed

Read-only public market data from Kraken as a `Market_data.Feed.t`: trades, best bid and
offer and the L2 book from the spot websocket v2, funding, mark and index from the
futures websocket. No API keys, no order entry.

Built with OxCaml and the Jane Street stack; depends on `market-data` (event types and
`Feed.S`) and `venue-net` (reconnecting websocket client).

## Library

```ocaml
let%bind (module Feed) =
  Kraken_feed.Live_feed.create Kraken_feed.Config.mainnet
    ~symbols:[ "BTC/USD" ] ~streams:[ Trades; Bbo; L2; Funding ]
in
Pipe.iter_without_pushback Feed.l2 ~f:(fun update -> ...)
```

`Normalizer` is the pure part (frame to events, per-symbol checksummed books) and is
what the tests drive; `Live_feed` adds one socket per stream, reconnects and resyncs.

`Live_feed.start` returns a handle with the feed (`Live_feed.feed`) and counters
(`Live_feed.stats`: frames received, frames that failed to parse, reconnects summed
over the sockets). `?time_source` (default the wall clock) stamps `recv_ts` and drives
pings, the silence watchdog and reconnect delays, so tests step them with a synthetic
clock (`test/test_reconnect_fake_clock.ml`).

`Raw_normalizer` is `Normalizer` as a `Market_data.Normalizer.S`, for rebuilding
`norm/` from market-recorder raw files:

```ocaml
Market_data.Rebuild_norm.command [ (module Kraken_feed.Raw_normalizer) ]
```
The wire format is described in [docs/kraken-ws-spec.md](docs/kraken-ws-spec.md).

## Command line

```
kraken-feed feed -symbol <SYM> [-symbol <SYM> ...] -streams trades,bbo,l2,funding \
  [-count N] [-l2-depth 10|25|100|500|1000] [-raw]
kraken-feed rebuild-norm -data-dir DIR -out NEW_DIR -date YYYY-MM-DD
```

Live output against the real venue, 2026-10-12 (each stream also ran for 10+ seconds;
timestamps print in the local zone):

```
$ kraken-feed feed -symbol BTC/USD -streams trades -count 2
(Trade
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:12.413160000+01:00))
  (recv_ts (2026-10-12 13:53:12.393721000+01:00)) (price 82820.6)
  (size 0.00034448) (side Buy) (trade_id 111081189)))
(Trade
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:12.413160000+01:00))
  (recv_ts (2026-10-12 13:53:12.393721000+01:00)) (price 82820.6)
  (size 0.00005) (side Buy) (trade_id 111081190)))
```

```
$ kraken-feed feed -symbol BTC/USD -streams bbo -count 2
(Bbo
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:12.726497000+01:00))
  (recv_ts (2026-10-12 13:53:12.839332000+01:00)) (bid_price 82824.7)
  (bid_size 0.30642391) (ask_price 82824.8) (ask_size 0.00140829)))
(Bbo
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:12.726497000+01:00))
  (recv_ts (2026-10-12 13:53:12.903547000+01:00)) (bid_price 82824.7)
  (bid_size 0.21596509) (ask_price 82824.8) (ask_size 0.00140829)))
```

```
$ kraken-feed feed -symbol BTC/USD -streams l2 -count 2
(L2
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:14.460755000+01:00))
  (recv_ts (2026-10-12 13:53:14.439728000+01:00)) (kind Snapshot)
  (bids
   (((price 82824.7) (size 0.19078425)) ((price 82823.8) (size 0.22303346))
    ((price 82823.7) (size 3.01845652)) ((price 82823.2) (size 0.01))
    ((price 82821) (size 3.01855463)) ((price 82820.8) (size 0.000051))
    ((price 82820.6) (size 0.3018569)) ((price 82820.5) (size 0.0225))
    ((price 82820.4) (size 0.02414863)) ((price 82819.5) (size 0.0023985))))
  (asks
   (((price 82824.8) (size 0.65054732)) ((price 82825.9) (size 0.18110284))
    ((price 82827.6) (size 3.01831977)) ((price 82828.1) (size 0.00070407))
    ((price 82828.9) (size 0.000051)) ((price 82833) (size 0.28533699))
    ((price 82833.1) (size 0.068351)) ((price 82834.1) (size 0.00014286))
    ((price 82834.7) (size 0.725268)) ((price 82836) (size 0.17089775))))))
(L2
 ((instrument ((venue Kraken) (symbol BTC/USD)))
  (exch_ts (2026-10-12 13:53:14.482575000+01:00))
  (recv_ts (2026-10-12 13:53:14.439839000+01:00)) (kind Delta)
  (bids (((price 82819.5) (size 0)) ((price 82819.4) (size 0.93858858))))
  (asks ())))
```

```
$ kraken-feed feed -symbol BTC/USD -streams funding -count 2
(Funding
 ((instrument ((venue Kraken) (symbol PF_XBTUSD)))
  (exch_ts (2026-10-12 13:53:14.923000000+01:00))
  (recv_ts (2026-10-12 13:53:14.925625000+01:00)) (rate 9.665204166667E-06)
  (next_funding_time (2026-10-12 14:00:00.000000000+01:00))
  (mark_price 82837.76229541) (index_price 82833.55)))
(Funding
 ((instrument ((venue Kraken) (symbol PF_XBTUSD)))
  (exch_ts (2026-10-12 13:53:15.005000000+01:00))
  (recv_ts (2026-10-12 13:53:15.087659000+01:00)) (rate 9.665204166667E-06)
  (next_funding_time (2026-10-12 14:00:00.000000000+01:00))
  (mark_price 82837.23537313) (index_price 82833.66)))
```

## Recorded fixtures and costs

`test/fixtures/raw/kraken/` holds a mainnet recording from market-recorder
(2026-10-12 13:34-13:35 UTC, BTC/USD and PF_XBTUSD, about 260 KB), trimmed and kept in
the recorder's raw layout so `rebuild-norm` runs on it directly. Every frame decodes and
normalizes; the book's 544 deltas pass their checksums:

| Stream | Frames | Events | Minor words per frame | Time per frame |
| --- | --- | --- | --- | --- |
| `trades` | 155 | 212 trades | 964 | 3.8 us |
| `bbo` | 158 | 148 BBOs | 789 | 3.9 us |
| `l2` | 553 | 1 snapshot, 544 deltas | 1294 | 6.0 us |
| `funding` | 64 | 19 funding | 868 | 6.3 us |

Words are pinned (within 10) in `test/test_allocation.ml`; times are from
`dune exec ./bench/main.exe -- -quota 3` on an M-series Mac, including JSON decoding.

## Coverage

| Stream | Venue channel | Endpoint | Verified live |
| --- | --- | --- | --- |
| `trades` | spot v2 `trade` (`snapshot: false`) | `wss://ws.kraken.com/v2` | yes |
| `bbo` | spot v2 `ticker` with `event_trigger: "bbo"` | `wss://ws.kraken.com/v2` | yes |
| `l2` | spot v2 `book`, depth 10 (or 25/100/500/1000), CRC32 checked on every message | `wss://ws.kraken.com/v2` | yes (depth 10 and 100, two symbols, 30s, no checksum mismatch) |
| `funding` | futures v1 `ticker` | `wss://futures.kraken.com/ws/v1` | yes |
| `private` | not supported (public feed only) | | n/a |

## Symbols

- Spot uses `BASE/QUOTE` with ISO codes: `BTC/USD`, `ETH/USD`. The v2 API rejects the
  legacy `XBT/USD`.
- Futures uses `PF_XBTUSD` for the linear perpetual (`PI_` inverse, `FI_` fixed
  maturity).
- `-symbol` takes either form. Spot streams map `PF_XBTUSD` to `BTC/USD`, the funding
  stream maps `BTC/USD` to `PF_XBTUSD` (`Kraken_feed.Symbols`). Instruments carry the
  name of the API that produced them: `kraken:BTC/USD` for trades/bbo/l2,
  `kraken:PF_XBTUSD` for funding.

## Behaviour

- One websocket per stream. Spot connections send `{"method":"ping"}` every 30s; the
  futures connection sends a websocket ping frame (it has no JSON ping and drops idle
  connections after 60s). A connection silent for two ping intervals is replaced.
- After a reconnect every stream resubscribes; books are cleared and the snapshot that
  follows is emitted as a fresh `Snapshot`.
- Book integrity: there are no sequence numbers on Kraken spot; every message carries a
  CRC32 of the top 10 levels. Number literals are kept as sent (frames are parsed with
  `Yojson.Raw`) so the checksum matches. A mismatch drops the book, unsubscribes and
  subscribes the symbol again, and waits for the new snapshot.
- Levels pushed beyond the subscribed depth are removed locally (Kraken does not send
  removals for them) and reported in the `Delta` as zero-size levels, so a consumer's
  book stays the same as the venue's.
- `funding` is emitted when the rate, next funding time, mark or index changes; the
  ticker arrives about once per second.

## Limitations

- Trades, BBO and L2 come from the spot market only. Kraken Futures has its own `trade`
  and `book` feeds for `PF_XBTUSD` (with sequence numbers), which are not wired in.
- `Funding.rate` is `relative_funding_rate`: the rate per funding period (hourly on
  Kraken perpetuals) as a fraction of the spot price. The absolute `funding_rate` and
  the predicted rates are not carried. `Funding.t` has no field for the period, so
  consumers comparing venues must know it is hourly here.
- Mark prices with more than 8 decimals are truncated to the fixed-point precision.
- Exchange timestamps can be a few tens of milliseconds ahead of `recv_ts` when the
  local clock lags.
- Spot symbols contain `/`; any consumer that builds file paths from the symbol (for
  example a raw frame recorder) needs to escape it.
