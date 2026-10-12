open! Core

let is_futures symbol =
  List.exists [ "PF_"; "PI_"; "FI_"; "FF_" ] ~f:(fun prefix ->
    String.is_prefix symbol ~prefix)
;;

let futures symbol =
  if is_futures symbol
  then symbol
  else (
    match String.lsplit2 symbol ~on:'/' with
    | Some (base, quote) ->
      let base = if String.equal base "BTC" then "XBT" else base in
      "PF_" ^ base ^ quote
    | None -> raise_s [%message "Kraken symbol has no futures equivalent" symbol])
;;

let spot symbol =
  match String.chop_prefix symbol ~prefix:"PF_" with
  | None when not (is_futures symbol) -> symbol
  | Some pair when String.length pair > 3 ->
    let n = String.length pair - 3 in
    let base = String.prefix pair n
    and quote = String.drop_prefix pair n in
    let base = if String.equal base "XBT" then "BTC" else base in
    base ^ "/" ^ quote
  | None | Some _ ->
    raise_s [%message "Kraken futures symbol has no spot equivalent" symbol]
;;
