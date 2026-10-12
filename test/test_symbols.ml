open! Core
open Kraken_feed

let%expect_test "spot and futures names" =
  List.iter [ "BTC/USD"; "ETH/USD"; "PF_XBTUSD"; "PF_ETHUSD"; "PI_XBTUSD" ] ~f:(fun s ->
    print_s
      [%sexp
        (s : string)
        , { futures =
              (Or_error.try_with (fun () -> Symbols.futures s) : string Or_error.t)
          ; spot = (Or_error.try_with (fun () -> Symbols.spot s) : string Or_error.t)
          }]);
  [%expect
    {|
    (BTC/USD ((futures (Ok PF_XBTUSD)) (spot (Ok BTC/USD))))
    (ETH/USD ((futures (Ok PF_ETHUSD)) (spot (Ok ETH/USD))))
    (PF_XBTUSD ((futures (Ok PF_XBTUSD)) (spot (Ok BTC/USD))))
    (PF_ETHUSD ((futures (Ok PF_ETHUSD)) (spot (Ok ETH/USD))))
    (PI_XBTUSD
     ((futures (Ok PI_XBTUSD))
      (spot (Error ("Kraken futures symbol has no spot equivalent" PI_XBTUSD)))))
    |}]
;;

let%expect_test "subscribe requests" =
  List.iter
    Market_data.Stream.[ Trades; Bbo; L2; Funding ]
    ~f:(fun stream ->
      print_endline (Live_feed.subscribe_request ~l2_depth:25 stream [ "BTC/USD" ]));
  print_endline
    (Live_feed.subscribe_request ~unsubscribe:true ~l2_depth:25 L2 [ "BTC/USD" ]);
  [%expect
    {|
    {"method":"subscribe","params":{"channel":"trade","snapshot":false,"symbol":["BTC/USD"]}}
    {"method":"subscribe","params":{"channel":"ticker","event_trigger":"bbo","symbol":["BTC/USD"]}}
    {"method":"subscribe","params":{"channel":"book","depth":25,"symbol":["BTC/USD"]}}
    {"event":"subscribe","feed":"ticker","product_ids":["BTC/USD"]}
    {"method":"unsubscribe","params":{"channel":"book","depth":25,"symbol":["BTC/USD"]}}
    |}]
;;
