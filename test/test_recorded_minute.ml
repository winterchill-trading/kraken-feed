(* Every frame of the recorded minute decodes and normalizes; per-stream counts. *)

open! Core
open Kraken_feed
module Md = Market_data

let kind : Md.Event.t -> string = function
  | Trade _ -> "trade"
  | Bbo _ -> "bbo"
  | L2 { kind = Snapshot; _ } -> "l2_snapshot"
  | L2 { kind = Delta; _ } -> "l2_delta"
  | Funding _ -> "funding"
;;

let%expect_test "every recorded frame decodes and normalizes" =
  List.iter Fixture.streams ~f:(fun stream ->
    let frames = Fixture.frames stream in
    let decode_errors =
      List.count frames ~f:(fun (_, frame) -> Or_error.is_error (Wire.of_string frame))
    in
    let normalizer = Normalizer.create () in
    let normalize_errors = ref 0 in
    let resubscribes = ref 0 in
    let events = String.Table.create () in
    List.iter frames ~f:(fun (recv_ts, frame) ->
      match Normalizer.frame normalizer ~recv_ts frame with
      | Error _ -> incr normalize_errors
      | Ok { events = e; resubscribe } ->
        resubscribes := !resubscribes + List.length resubscribe;
        List.iter e ~f:(fun event -> Hashtbl.incr events (kind event)));
    print_s
      [%message
        ""
          (stream : Md.Stream.t)
          ~frames:(List.length frames : int)
          (decode_errors : int)
          ~normalize_errors:(!normalize_errors : int)
          ~resubscribes:(!resubscribes : int)
          ~events:
            (Hashtbl.to_alist events |> List.sort ~compare:[%compare: string * int]
             : (string * int) list)]);
  [%expect
    {|
    ((stream Trades) (frames 155) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((trade 212))))
    ((stream Bbo) (frames 158) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((bbo 148))))
    ((stream L2) (frames 553) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((l2_delta 544) (l2_snapshot 1))))
    ((stream Funding) (frames 64) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((funding 19))))
    |}]
;;
