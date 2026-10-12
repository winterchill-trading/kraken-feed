(* [Live_feed.stats] with frames pushed by a scripted local websocket server. *)

open! Core
open Async
open Kraken_feed

let trade =
  {|{"channel":"trade","type":"update","data":[{"symbol":"BTC/USD","side":"sell","price":82471.1,"qty":0.00002396,"ord_type":"limit","trade_id":111088026,"timestamp":"2026-10-12T13:34:56.207110Z"}]}|}
;;

let%expect_test "a malformed frame is counted and skipped" =
  Log.Global.set_output [];
  let%bind server = Fake_ws.start () in
  let%bind live =
    Live_feed.start (Fake_ws.config server) ~symbols:[ "BTC/USD" ] ~streams:[ Trades ]
  in
  let module F = (val Live_feed.feed live : Market_data.Feed.S) in
  let%bind (_ : bool) =
    Fake_ws.wait_until (fun () -> not (List.is_empty (Fake_ws.received server)))
  in
  print_s [%sexp (Fake_ws.received server : string list)];
  [%expect
    {| ("{\"method\":\"subscribe\",\"params\":{\"channel\":\"trade\",\"snapshot\":false,\"symbol\":[\"BTC/USD\"]}}") |}];
  Fake_ws.send server {|{"channel":"heartbeat"}|};
  Fake_ws.send server {|{"channel":"trade","type":"update","data":[{"symbol":|};
  Fake_ws.send server trade;
  let%bind trade = Pipe.read F.trades in
  (match trade with
   | `Ok trade -> print_s [%sexp (trade.trade_id : string)]
   | `Eof -> print_endline "eof");
  print_s [%sexp (Live_feed.stats live : Live_feed.Stats.t)];
  [%expect {|
    111088026
    ((frames 3) (parse_errors 1) (reconnects 0))
    |}];
  let%bind () = F.close () in
  Fake_ws.close server
;;
