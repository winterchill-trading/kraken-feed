open! Core
module Md = Market_data

let data_dir = "fixtures"
let date = Date.of_string "2026-10-12"
let streams : Md.Stream.t list = [ Trades; Bbo; L2; Funding ]

let symbol_dir : Md.Stream.t -> string = function
  | Funding -> "PF_XBTUSD"
  | Trades | Bbo | L2 | Private -> "BTC_USD"
;;

let frames stream =
  let dir =
    data_dir
    ^/ sprintf
         "raw/kraken/%s/%s/2026/10/12"
         (Md.Stream.to_string stream)
         (symbol_dir stream)
  in
  List.concat_map [ "13-34.ndjson"; "13-35.ndjson" ] ~f:(fun file ->
    In_channel.read_lines (dir ^/ file)
    |> List.map ~f:(fun line ->
      let recv_ts, frame = String.lsplit2_exn line ~on:' ' in
      Time_ns.of_string_with_utc_offset recv_ts, frame))
;;
