(* [Market_data.Rebuild_norm] over the recorded minute with [Raw_normalizer], then the
   event logs read back. *)

open! Core
open Async
open Kraken_feed
module Md = Market_data

let with_temp_dir f =
  let%bind dir = Unix.mkdtemp (Filename.temp_dir_name ^/ "kraken-feed-test") in
  Monitor.protect
    (fun () -> f dir)
    ~finally:(fun () ->
      Process.run_expect_no_stdout_exn ~prog:"rm" ~args:[ "-rf"; dir ] ())
;;

let instrument : Md.Stream.t -> Md.Instrument.t = function
  | Funding -> Normalizer.instrument "PF_XBTUSD"
  | Trades | Bbo | L2 | Private -> Normalizer.instrument "BTC/USD"
;;

let%expect_test "rebuild norm from the recorded minute" =
  with_temp_dir (fun dir ->
    let out_dir = dir ^/ "norm" in
    let%bind stats =
      Md.Rebuild_norm.run
        ~normalizers:[ (module Raw_normalizer) ]
        ~data_dir:Fixture.data_dir
        ~out_dir
        Fixture.date
    in
    print_s [%sexp (stats : Md.Rebuild_norm.Stats.t Or_error.t)];
    let%map () =
      Deferred.List.iter Fixture.streams ~how:`Sequential ~f:(fun stream ->
        let path =
          Md.Event_log.path ~dir:out_dir (instrument stream) stream Fixture.date
        in
        let%map events, tail = Md.Event_log.load_file path in
        let first, last =
          let recv (e : Md.Event.t) = Helpers.utc (Md.Event.recv_ts e) in
          recv (List.hd_exn events), recv (List.last_exn events)
        in
        print_s
          [%message
            ""
              ~file:(String.chop_prefix_exn path ~prefix:(dir ^ "/") : string)
              ~events:(List.length events : int)
              (first : string)
              (last : string)
              (tail : Md.Framed.Tail.t)])
    in
    [%expect
      {|
      (Ok
       ((files 8) (frames 930) (disconnects 0) (events 924) (frame_errors 0)
        (first_errors ()) (skipped_files 0) (skipped_venues ())))
      ((file norm/kraken/BTC_USD/norm/trades/2026-10-12.bin) (events 212)
       (first 2026-10-12T13:34:56.130017000Z) (last 2026-10-12T13:35:59.654237000Z)
       (tail Clean))
      ((file norm/kraken/BTC_USD/norm/bbo/2026-10-12.bin) (events 148)
       (first 2026-10-12T13:34:57.254263000Z) (last 2026-10-12T13:35:04.897061000Z)
       (tail Clean))
      ((file norm/kraken/BTC_USD/norm/l2/2026-10-12.bin) (events 545)
       (first 2026-10-12T13:34:58.534726000Z) (last 2026-10-12T13:35:05.062351000Z)
       (tail Clean))
      ((file norm/kraken/PF_XBTUSD/norm/funding/2026-10-12.bin) (events 19)
       (first 2026-10-12T13:34:58.713662000Z) (last 2026-10-12T13:35:16.308011000Z)
       (tail Clean))
      |}])
;;
