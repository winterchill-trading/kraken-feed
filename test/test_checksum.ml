open! Core
open Kraken_feed

let%expect_test "crc32 of a known string" =
  print_s [%sexp (Checksum.crc32 "123456789" : int)];
  [%expect {| 3421780262 |}]
;;

let%expect_test "number formatting drops the point and leading zeros" =
  List.iter [ "45285.2"; "0.00100000"; "82690.0"; "0.10000000"; "100" ] ~f:(fun s ->
    print_endline (Checksum.format_number (Wire.Number.of_string s)));
  [%expect {|
    452852
    100000
    826900
    10000000
    100
    |}]
;;

let%expect_test "checksum of a live snapshot" =
  match Wire.of_string Samples.snapshot with
  | Ok (Book (Snapshot, [ book ])) ->
    print_s
      [%sexp
        { expected : int = book.checksum
        ; computed : int = Checksum.of_levels ~bids:book.bids ~asks:book.asks
        }];
    [%expect {| ((expected 3892606613) (computed 3892606613)) |}]
  | other -> print_s [%sexp (other : Wire.t Or_error.t)]
;;
