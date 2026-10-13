open! Core
open Kraken_feed

let%expect_test "exponent literals parse exactly, without a float" =
  List.iter
    [ "9.6e-6"
    ; "9.665204166667e-6"
    ; "1.708608333333E-06"
    ; "-2.5e-3"
    ; "1e2"
    ; "1.5e+3"
    ; "1.23456789e-8"
    ; "0.00005100"
    ]
    ~f:(fun s ->
      let n = Wire.Number.of_string s in
      let price = Wire.Number.to_price n in
      let size = Wire.Number.to_size n in
      print_s [%message s (price : Market_data.Price.t) (size : Market_data.Size.t)]);
  [%expect
    {|
    (9.6e-6 (price 0.0000096) (size 0.0000096))
    (9.665204166667e-6 (price 0.00000966) (size 0.00000966))
    (1.708608333333E-06 (price 0.0000017) (size 0.0000017))
    (-2.5e-3 (price -0.0025) (size -0.0025))
    (1e2 (price 100) (size 100))
    (1.5e+3 (price 1500) (size 1500))
    (1.23456789e-8 (price 0.00000001) (size 0.00000001))
    (0.00005100 (price 0.000051) (size 0.000051))
    |}]
;;

let%expect_test "malformed exponent literals raise" =
  List.iter [ "e5"; "1e"; "1e-"; "1.2.3e4"; "1ex"; "1e99" ] ~f:(fun s ->
    let price =
      Or_error.try_with (fun () -> Wire.Number.to_price (Wire.Number.of_string s))
    in
    print_s [%message s (price : Market_data.Price.t Or_error.t)]);
  [%expect
    {|
    (e5 (price (Error (Invalid_argument "Kraken number: cannot parse \"e5\""))))
    (1e (price (Error (Invalid_argument "Kraken number: cannot parse \"1e\""))))
    (1e-
     (price (Error (Invalid_argument "Kraken number: cannot parse \"1e-\""))))
    (1.2.3e4
     (price (Error (Invalid_argument "Kraken number: cannot parse \"1.2.3e4\""))))
    (1ex
     (price (Error (Invalid_argument "Kraken number: cannot parse \"1ex\""))))
    (1e99
     (price (Error (Invalid_argument "Kraken number: cannot parse \"1e99\""))))
    |}]
;;
