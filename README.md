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
The wire format is described in [docs/kraken-ws-spec.md](docs/kraken-ws-spec.md).

## Command line

```
kraken-feed feed -symbol <SYM> [-symbol <SYM> ...] -streams trades,bbo,l2,funding \
  [-count N] [-l2-depth 10|25|100|500|1000] [-raw]
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

