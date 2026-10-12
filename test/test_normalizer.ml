open! Core
open Kraken_feed

let feed normalizer frame =
  Helpers.print_output (Normalizer.frame normalizer ~recv_ts:Helpers.recv_ts frame)
;;

let%expect_test "trades (docs sample)" =
  feed
    (Normalizer.create ())
    {|{"channel":"trade","type":"update","data":[{"symbol":"MATIC/USD","side":"sell","price":0.5117,"qty":40.0,"ord_type":"market","trade_id":4665906,"timestamp":"2023-09-25T07:49:37.708706Z"},{"symbol":"MATIC/USD","side":"buy","price":0.5118,"qty":1.5,"ord_type":"limit","trade_id":4665907,"timestamp":"2023-09-25T07:49:37.708706Z"}]}|};
  [%expect
    {|
    (Trade
     ((instrument kraken:MATIC/USD) (exch_ts 2023-09-25T07:49:37.708706000Z)
      (price 0.5117) (size 40) (side Sell) (trade_id 4665906)))
    (Trade
     ((instrument kraken:MATIC/USD) (exch_ts 2023-09-25T07:49:37.708706000Z)
      (price 0.5118) (size 1.5) (side Buy) (trade_id 4665907)))
    |}]
;;

let%expect_test "bbo ticker (live sample)" =
  feed
    (Normalizer.create ())
    {|{"channel":"ticker","type":"update","data":[{"symbol":"BTC/USD","bid":82689.0,"bid_qty":0.87139253,"ask":82689.1,"ask_qty":0.00515350,"last":82689.0,"volume":1849.23249967,"vwap":83601.5,"low":82565.7,"high":84250.0,"change":-364.9,"change_pct":-0.44,"trades":107540,"timestamp":"2026-10-12T12:42:25.919160Z"}]}|};
  [%expect
    {|
    (Bbo
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:25.919160000Z)
      (bid 82689) (bid_size 0.87139253) (ask 82689.1) (ask_size 0.0051535)))
    |}]
;;

let futures_ticker ~mark =
  sprintf
    {|{"time":1791808963770,"product_id":"PF_XBTUSD","funding_rate":0.8052600612714028,"funding_rate_prediction":0.1413222074336391,"relative_funding_rate":9.665204166667e-6,"relative_funding_rate_prediction":1.708608333333e-6,"next_funding_rate_time":1791810000000,"leverage":"100x","premium":0.0,"feed":"ticker","bid":82719.0,"ask":82720.0,"bid_size":0.4682,"ask_size":0.2276,"volume":3991.2036,"dtm":0,"index":82711.91,"last":82719.0,"change":-0.41,"suspended":false,"tag":"perpetual","pair":"XBT:USD","openInterest":2366.2175,"markPrice":%s,"maturityTime":0,"post_only":false,"volumeQuote":333311695.1864,"open":83059.0,"high":84273.0,"low":82526.0}|}
    mark
;;

let%expect_test "futures ticker becomes funding, repeats are dropped" =
  let normalizer = Normalizer.create () in
  feed normalizer (futures_ticker ~mark:"82715.99414653402");
  [%expect
    {|
    (Funding
     ((instrument kraken:PF_XBTUSD) (exch_ts 2026-10-12T12:42:43.770000000Z)
      (rate 9.665204166667E-06)
      (next_funding_time 2026-10-12T13:00:00.000000000Z) (mark 82715.99414653)
      (index 82711.91)))
    |}];
  feed normalizer (futures_ticker ~mark:"82715.99414653402");
  [%expect {| |}];
  feed normalizer (futures_ticker ~mark:"82716.5");
  [%expect
    {|
    (Funding
     ((instrument kraken:PF_XBTUSD) (exch_ts 2026-10-12T12:42:43.770000000Z)
      (rate 9.665204166667E-06)
      (next_funding_time 2026-10-12T13:00:00.000000000Z) (mark 82716.5)
      (index 82711.91)))
    |}]
;;

let%expect_test "control frames produce nothing" =
  let normalizer = Normalizer.create () in
  List.iter
    [ {|{"channel":"heartbeat"}|}
    ; {|{"channel":"status","type":"update","data":[{"version":"2.0.10","system":"online","api_version":"v2","connection_id":2145014738088927114}]}|}
    ; {|{"method":"subscribe","result":{"channel":"book","depth":10,"snapshot":true,"symbol":"BTC/USD"},"success":true,"time_in":"2026-10-12T12:42:20.851254Z","time_out":"2026-10-12T12:42:20.851305Z"}|}
    ; {|{"method":"pong","time_in":"2026-10-12T12:46:18.052882Z","time_out":"2026-10-12T12:46:18.052898Z"}|}
    ; {|{"event":"info","version":1}|}
    ; {|{"event":"subscribed","feed":"ticker","product_ids":["PF_XBTUSD"]}|}
    ; {|{"channel":"ohlc","type":"update","data":[]}|}
    ]
    ~f:(feed normalizer);
  [%expect {| |}]
;;

let print_decoded frame =
  match Wire.of_string frame with
  | Ok wire -> print_s [%sexp (wire : Wire.t)]
  | Error _ -> print_endline "Error"
;;

let%expect_test "rejections decode as failed acks" =
  print_decoded
    {|{"error":"Currency pair not supported XBT/USD","method":"subscribe","success":false,"symbol":"XBT/USD","time_in":"2026-10-12T12:42:08.543367Z","time_out":"2026-10-12T12:42:08.543402Z"}|};
  print_decoded {|{"event":"alert","message":"Bad websocket message"}|};
  [%expect
    {|
    (Ack
     ((method_ subscribe) (success false) (channel ()) (symbol (XBT/USD))
      (error ("Currency pair not supported XBT/USD"))))
    (Futures_event (event alert) (message ("Bad websocket message")))
    |}]
;;

let%expect_test "bad frames are errors" =
  List.iter
    [ "not json"
    ; {|[1,2,3]|}
    ; {|{"foo":1}|}
    ; {|{"channel":"trade","type":"update","data":[{"symbol":"BTC/USD","side":"up","price":1,"qty":1,"ord_type":"limit","trade_id":1,"timestamp":"2026-10-12T12:00:00Z"}]}|}
    ; {|{"channel":"book","type":"update","data":[{"symbol":"BTC/USD","bids":[],"asks":[]}]}|}
    ; {|{"channel":"ticker","type":"bogus","data":[]}|}
    ; {|{"channel":"trade","type":"update","data":[{"symbol":"BTC/USD","side":"buy","price":"1","qty":1,"ord_type":"limit","trade_id":1,"timestamp":"yesterday"}]}|}
    ]
    ~f:print_decoded;
  [%expect
    {|
    Error
    Error
    Error
    Error
    Error
    Error
    Error
    |}]
;;
