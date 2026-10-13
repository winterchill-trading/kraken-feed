(* Minor words allocated per Live_feed message: what [Normalizer.frame] (decode plus
   normalization, the work Live_feed does per websocket frame) allocates on the recorded
   minute. The timing benchmark is in bench/. Counts differ by a few words between macOS
   and Linux, hence [Helpers.approx]. *)

open! Core
open Kraken_feed
module Md = Market_data

let words f =
  let before = Gc.minor_words () in
  f ();
  Gc.minor_words () - before
;;

(* Pinned counts. macOS and Linux differ by a few words; [Helpers.approx] allows 10. *)
(* Repinned 2026-10-13 from 964/789/1294/868, with no change in this repo: fixed-decimal
   now parses prices and sizes in place. Identical on macOS and Linux CI. *)
let expected : Md.Stream.t -> int = function
  | Trades -> 925
  | Bbo -> 735
  | L2 -> 1209
  | Funding -> 842
  | Private -> 0
;;

let%expect_test "minor words per Live_feed message" =
  List.iter Fixture.streams ~f:(fun stream ->
    let t = Normalizer.create () in
    let frames = Fixture.frames stream in
    let total =
      List.sum (module Int) frames ~f:(fun (recv_ts, frame) ->
        words (fun () ->
          ignore
            (Sys.opaque_identity (Normalizer.frame t ~recv_ts frame)
             : Normalizer.Output.t Or_error.t)))
    in
    let n = List.length frames in
    let bytes = List.sum (module Int) frames ~f:(fun (_, frame) -> String.length frame) in
    print_s
      [%message
        ""
          (stream : Md.Stream.t)
          ~frames:(n : int)
          ~words_per_frame:
            (Helpers.approx ~expected:(expected stream) ~tolerance:10 (total / n)
             : Sexp.t)
          ~bytes_per_frame:(bytes / n : int)]);
  [%expect
    {|
    ((stream Trades) (frames 155) (words_per_frame 925+-10)
     (bytes_per_frame 245))
    ((stream Bbo) (frames 158) (words_per_frame 735+-10) (bytes_per_frame 297))
    ((stream L2) (frames 553) (words_per_frame 1209+-10) (bytes_per_frame 192))
    ((stream Funding) (frames 64) (words_per_frame 842+-10)
     (bytes_per_frame 640))
    |}]
;;
