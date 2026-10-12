(* [Live_feed]'s gaps pipe on a synthetic clock: a checksum mismatch and a reconnect each
   report a [Resync] gap, already queued when the snapshot that follows is read. *)

open! Core
open Async
open Kraken_feed

let ms = Time_ns.Span.of_int_ms

let%expect_test "checksum mismatch and reconnect gaps precede the new snapshot" =
  Log.Global.set_output [];
  let%bind server = Fake_ws.start () in
  let clock = Time_source.create ~now:Time_ns.epoch () in
  let%bind live =
    Live_feed.start
      ~time_source:(Time_source.read_only clock)
      (Fake_ws.config server)
      ~symbols:[ "BTC/USD" ]
      ~streams:[ L2 ]
  in
  let module F = (val Live_feed.feed_with_gaps live : Market_data.Feed.With_gaps.S) in
  let subscribes () =
    List.count (Fake_ws.received server) ~f:(fun frame ->
      String.is_substring frame ~substring:{|"method":"subscribe"|})
  in
  (* Reads the next L2 event and prints it with every gap queued before it. *)
  let next_l2 () =
    match%map Pipe.read F.l2 with
    | `Eof -> print_endline "eof"
    | `Ok (update : Market_data.L2_update.t) ->
      let gaps =
        match Pipe.read_now' F.gaps with
        | `Ok gaps -> Queue.to_list gaps
        | `Nothing_available | `Eof -> []
      in
      List.iter gaps ~f:(fun gap -> print_s [%sexp (gap : Market_data.Gap.t)]);
      print_s
        [%message
          "l2"
            ~kind:(update.kind : Market_data.L2_update.Kind.t)
            ~recv_ts_ms:(Time_ns.to_int_ns_since_epoch update.recv_ts / 1_000_000 : int)]
  in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> subscribes () = 1) in
  Fake_ws.send server Samples.snapshot;
  let%bind () = next_l2 () in
  [%expect {| (l2 (kind Snapshot) (recv_ts_ms 0)) |}];
  (* [update1] is lost: [update2]'s checksum fails and the symbol is resubscribed. *)
  let%bind () = Time_source.advance_by_alarms_by clock (ms 100) in
  Fake_ws.send server Samples.update2;
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> subscribes () = 2) in
  Fake_ws.send server Samples.snapshot;
  let%bind () = next_l2 () in
  [%expect
    {|
    ((recv_ts "1970-01-01 00:00:00.1Z") (venue Kraken)
     (instrument (((venue Kraken) (symbol BTC/USD)))) (stream (L2))
     (reason Resync))
    (l2 (kind Snapshot) (recv_ts_ms 100))
    |}];
  (* A dropped socket: the first backoff is 0.5s +/- 20%, so 0.6s always reconnects. *)
  let%bind () = Fake_ws.drop server in
  let%bind () = Clock_ns.after (ms 50) in
  let%bind () = Time_source.advance_by_alarms_by clock (ms 600) in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> subscribes () = 3) in
  Fake_ws.send server Samples.update1;
  Fake_ws.send server Samples.snapshot;
  let%bind () = next_l2 () in
  [%expect
    {|
    ((recv_ts "1970-01-01 00:00:00.7Z") (venue Kraken) (instrument ())
     (stream (L2)) (reason Resync))
    (l2 (kind Snapshot) (recv_ts_ms 700))
    |}];
  print_s [%sexp (Live_feed.stats live : Live_feed.Stats.t)];
  [%expect {| ((frames 5) (parse_errors 0) (reconnects 1)) |}];
  let%bind () = F.close () in
  Fake_ws.close server
;;
