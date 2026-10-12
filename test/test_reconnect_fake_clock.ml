(* [Live_feed] reconnecting on a synthetic clock: the backoff sleep, the resubscription
   and [recv_ts] all follow the clock. Sockets are real (127.0.0.1), so the test waits in
   real time for I/O and steps the clock for every delay. *)

open! Core
open Async
open Kraken_feed

let ms = Time_ns.Span.of_int_ms

let trade =
  {|{"channel":"trade","type":"update","data":[{"symbol":"BTC/USD","side":"sell","price":82471.1,"qty":0.00002396,"ord_type":"limit","trade_id":111088026,"timestamp":"2026-10-12T13:34:56.207110Z"}]}|}
;;

let%expect_test "reconnects on a synthetic clock and resubscribes" =
  Log.Global.set_output [];
  let%bind server = Fake_ws.start () in
  let clock = Time_source.create ~now:Time_ns.epoch () in
  let%bind live =
    Live_feed.start
      ~time_source:(Time_source.read_only clock)
      (Fake_ws.config server)
      ~symbols:[ "BTC/USD" ]
      ~streams:[ Trades ]
  in
  let module F = (val Live_feed.feed live : Market_data.Feed.S) in
  let subscribes () =
    List.count (Fake_ws.received server) ~f:(String.is_substring ~substring:"subscribe")
  in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> subscribes () = 1) in
  let%bind () = Fake_ws.drop server in
  (* The first backoff is 0.5s with 20% jitter: nothing before 0.4s, a new connection by
     0.6s. Real I/O is given time to happen at each step. *)
  let%bind () = Clock_ns.after (ms 50) in
  let%bind () = Time_source.advance_by_alarms_by clock (ms 390) in
  let%bind () = Clock_ns.after (ms 50) in
  print_s [%message "after 0.39s" ~connections:(Fake_ws.connections server : int)];
  let%bind () = Time_source.advance_by_alarms_by clock (ms 210) in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> subscribes () = 2) in
  print_s
    [%message
      "after 0.6s"
        ~connections:(Fake_ws.connections server : int)
        ~subscribes:(subscribes () : int)
        ~stats:(Live_feed.stats live : Live_feed.Stats.t)];
  Fake_ws.send server trade;
  let%bind trade = Pipe.read F.trades in
  (match trade with
   | `Ok trade ->
     print_s
       [%message
         "" ~recv_ts_ms:(Time_ns.to_int_ns_since_epoch trade.recv_ts / 1_000_000 : int)]
   | `Eof -> print_endline "eof");
  [%expect
    {|
    ("after 0.39s" (connections 1))
    ("after 0.6s" (connections 2) (subscribes 2)
     (stats ((frames 0) (parse_errors 0) (reconnects 1))))
    (recv_ts_ms 600)
    |}];
  let%bind () = F.close () in
  Fake_ws.close server
;;
