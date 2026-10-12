# Kraken public websocket: what this feed uses

Sources: docs.kraken.com (spot websocket v2: `trade`, `ticker`, `book`, `ping`, book
checksum guide; futures websocket v1: `ticker`, connection guide). Samples below were
captured from the live endpoints on 2026-10-12 unless marked "docs".

Kraken has two separate public websocket APIs:

| API | URL | Used for |
| --- | --- | --- |
| Spot v2 | `wss://ws.kraken.com/v2` | trades, BBO, L2 book (spot pairs, e.g. `BTC/USD`) |
| Futures v1 | `wss://futures.kraken.com/ws/v1` | funding, mark and index of perpetuals (e.g. `PF_XBTUSD`) |

No authentication is needed for any channel below.

## Spot v2

### Symbols

ISO-ish `BASE/QUOTE`, e.g. `BTC/USD`, `ETH/USD`. The old `XBT/USD` names are rejected
by v2:

```json
{"error":"Currency pair not supported XBT/USD","method":"subscribe","success":false,"symbol":"XBT/USD","time_in":"2026-10-12T12:42:08.543367Z","time_out":"2026-10-12T12:42:08.543402Z"}
```

### Requests and acks

```json
{"method":"subscribe","params":{"channel":"trade","symbol":["BTC/USD"],"snapshot":false}}
{"method":"subscribe","params":{"channel":"ticker","symbol":["BTC/USD"],"event_trigger":"bbo"}}
{"method":"subscribe","params":{"channel":"book","symbol":["BTC/USD"],"depth":10}}
{"method":"unsubscribe","params":{"channel":"book","symbol":["BTC/USD"],"depth":10}}
```

One ack per symbol:

```json
{"method":"subscribe","result":{"channel":"book","depth":10,"snapshot":true,"symbol":"BTC/USD"},"success":true,"time_in":"2026-10-12T12:42:20.851254Z","time_out":"2026-10-12T12:42:20.851305Z"}
```

Every connection first receives a `status` message, then a `heartbeat`
(`{"channel":"heartbeat"}`) about once per second while any subscription is active.

```json
{"channel":"status","type":"update","data":[{"version":"2.0.10","system":"online","api_version":"v2","connection_id":2145014738088927114, ...}]}
```

### Numbers

Prices and quantities are JSON numbers printed at the pair's precision, including
trailing zeros (`82690.0`, `0.00005100`). Parsing them as floats loses the digits the
book checksum needs, so the feed reads frames with `Yojson.Raw`, which keeps number
literals as strings.

### `trade`

`snapshot` (default false) replays the last 50 trades as a `"snapshot"` message.
`side` is the taker side, `trade_id` is a per-pair sequence number, `timestamp` RFC3339
with microseconds. Sample (docs):

```json
{"channel":"trade","type":"update","data":[{"symbol":"MATIC/USD","side":"sell","price":0.5117,"qty":40.0,"ord_type":"market","trade_id":4665906,"timestamp":"2023-09-25T07:49:37.708706Z"}]}
```

### `ticker` with `event_trigger: "bbo"`

Pushes on every change of the best bid or offer (default trigger is `trades`). A
snapshot comes first.

```json
{"channel":"ticker","type":"update","data":[{"symbol":"BTC/USD","bid":82689.0,"bid_qty":0.87139253,"ask":82689.1,"ask_qty":0.00515350,"last":82689.0,"volume":1849.23249967,"vwap":83601.5,"low":82565.7,"high":84250.0,"change":-364.9,"change_pct":-0.44,"trades":107540,"timestamp":"2026-10-12T12:42:25.919160Z"}]}
```

### `book`

`depth` is one of 10, 25, 100, 500, 1000 (default 10). After the ack the server sends a
`snapshot`, then `update`s with only the changed levels (either side may be empty, the
same price can appear more than once in one message, apply in order). `qty` 0 removes a
level.

```json
{"channel":"book","type":"snapshot","data":[{"symbol":"BTC/USD","bids":[{"price":82689.0,"qty":0.00055351},{"price":82688.7,"qty":0.00005100}, ...],"asks":[{"price":82689.1,"qty":1.23752222},{"price":82689.8,"qty":0.14580116}, ...],"checksum":3892606613,"timestamp":"2026-10-12T12:42:21.094243Z"}]}
{"channel":"book","type":"update","data":[{"symbol":"BTC/USD","bids":[{"price":82683.6,"qty":0.00000000},{"price":82675.6,"qty":3.02386325}],"asks":[],"checksum":350739468,"timestamp":"2026-10-12T12:42:21.330249Z"}]}
```

Sequencing: there is no sequence number. Integrity is checked with `checksum` on every
message:

1. Apply all levels of the message, drop zero-quantity levels.
2. Truncate each side to the subscribed depth. The server does not send deletes for
   levels pushed out of range, so the client must drop them.
3. Asks: the 10 lowest, ascending. For each level take the price literal, remove the
   `.` and leading zeros, then the same for the quantity, and append both.
4. Bids: the 10 highest, descending, same formatting.
5. CRC32 (IEEE) of `asks ^ bids` as an unsigned 32-bit integer must equal `checksum`.

Docs example: best ask `45285.2` / `0.00100000` contributes `452852100000`.

On mismatch the book is invalid: unsubscribe and subscribe again to get a new snapshot.
Updates before the first snapshot are dropped.

### Keepalive and limits

- Application ping: `{"method":"ping","req_id":101}` answered by
  `{"method":"pong","req_id":101,"time_in":...,"time_out":...}`. The docs give no
  required interval; the heartbeat channel keeps an idle connection busy anyway.
- The docs pages for these channels state no message rate limits. Kraken applies a
  connection-attempt limit per IP at its edge; reconnects use exponential backoff.

## Futures v1

### Symbols

`PF_XBTUSD` (multi-collateral linear perpetual), `PI_XBTUSD` (inverse perpetual),
`FI_...` (fixed maturity).

### `ticker`

```json
{"event":"subscribe","feed":"ticker","product_ids":["PF_XBTUSD"]}
```

On connect: `{"event":"info","version":1}`, then
`{"event":"subscribed","feed":"ticker","product_ids":["PF_XBTUSD"]}`, then a ticker about
once per second:

```json
{"time":1791808963770,"product_id":"PF_XBTUSD","funding_rate":0.8052600612714028,"funding_rate_prediction":0.1413222074336391,"relative_funding_rate":9.665204166667e-6,"relative_funding_rate_prediction":1.708608333333e-6,"next_funding_rate_time":1791810000000,"leverage":"100x","premium":0.0,"feed":"ticker","bid":82719.0,"ask":82720.0,"bid_size":0.4682,"ask_size":0.2276,"volume":3991.2036,"dtm":0,"index":82711.91,"last":82719.0,"change":-0.41,"suspended":false,"tag":"perpetual","pair":"XBT:USD","openInterest":2366.2175,"markPrice":82715.99414653402,"maturityTime":0,"post_only":false,"volumeQuote":333311695.1864,"open":83059.0,"high":84273.0,"low":82526.0}
```

- `time`: server time, epoch ms.
- `funding_rate`: absolute rate (quote currency per contract per period); omitted when
  zero.
- `relative_funding_rate`: the rate as a fraction of the spot price per funding period
  (hourly on `PF_` perpetuals). This is what `Funding.rate` carries.
- `next_funding_rate_time`: epoch ms of the next funding (the docs call it a duration, the
  live value is an absolute time).
- `markPrice`, `index`: mark and index price. `markPrice` has more than 8 decimals and
  is truncated to the fixed-point precision.

### Keepalive

The client must send something at least every 60 seconds or the server closes the
connection. There is no JSON ping: `{"event":"ping"}` is answered with
`{"event":"alert","message":"Bad websocket message"}`. The feed sends a websocket ping
frame every 30 seconds instead.

Errors come back as `{"event":"error","message":"..."}` or
`{"event":"alert","message":"..."}`.

## Resubscribing a book

Subscribing to a book that is already subscribed is rejected, so a resync sends
`unsubscribe` then `subscribe` on the same connection. Verified live: the venue acks
both and sends a fresh `snapshot`.
