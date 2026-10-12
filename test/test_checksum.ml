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

(* A BTC/USD depth 10 snapshot captured from the live API on 2026-10-12. *)
let snapshot =
  {|{"channel":"book","type":"snapshot","data":[{"symbol":"BTC/USD","bids":[{"price":82689.0,"qty":0.00055351},{"price":82688.7,"qty":0.00005100},{"price":82687.4,"qty":0.00090703},{"price":82684.5,"qty":0.00005100},{"price":82683.8,"qty":0.00012081},{"price":82683.7,"qty":0.22354849},{"price":82683.6,"qty":3.02357136},{"price":82681.5,"qty":3.02364775},{"price":82680.4,"qty":0.00005100},{"price":82676.3,"qty":0.00005100}],"asks":[{"price":82689.1,"qty":1.23752222},{"price":82689.8,"qty":0.14580116},{"price":82690.0,"qty":1.89824541},{"price":82690.1,"qty":3.02333839},{"price":82690.2,"qty":0.02418666},{"price":82690.7,"qty":0.00550000},{"price":82691.9,"qty":1.43926316},{"price":82692.0,"qty":3.02341747},{"price":82692.5,"qty":0.00030000},{"price":82692.7,"qty":0.00005100}],"checksum":3892606613,"timestamp":"2026-10-12T12:42:21.094243Z"}]}|}
;;

let%expect_test "checksum of a live snapshot" =
  match Wire.of_string snapshot with
  | Ok (Book (Snapshot, [ book ])) ->
    print_s
      [%sexp
        { expected : int = book.checksum
        ; computed : int = Checksum.of_levels ~bids:book.bids ~asks:book.asks
        }];
    [%expect {| ((expected 3892606613) (computed 3892606613)) |}]
  | other -> print_s [%sexp (other : Wire.t Or_error.t)]
;;
