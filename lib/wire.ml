open! Core
module Md = Market_data

module Number = struct
  type t = string [@@deriving sexp_of, equal]

  let of_string = Fn.id
  let to_string = Fn.id
  let is_exponent t = String.exists t ~f:(fun c -> Char.equal c 'e' || Char.equal c 'E')
  let to_float = Float.of_string
  let invalid t = invalid_argf "Kraken number: cannot parse %S" t ()

  (* Kraken prints small values such as funding rates as ["9.6e-6"], which the decimal
     parser does not accept. Shifting the mantissa by the exponent in integer units keeps
     the value exact instead of rounding it through a float. *)
  let exponent_units t =
    let len = String.length t in
    let pos = ref 0 in
    let negative =
      match String.unsafe_get t 0 with
      | '-' ->
        incr pos;
        true
      | '+' ->
        incr pos;
        false
      | _ -> false
    in
    let mantissa = ref 0 in
    let digits = ref 0 in
    let fraction_digits = ref 0 in
    let in_fraction = ref false in
    while
      !pos < len
      && not
           (Char.equal (String.unsafe_get t !pos) 'e'
            || Char.equal (String.unsafe_get t !pos) 'E')
    do
      let c = String.unsafe_get t !pos in
      if Char.equal c '.' && not !in_fraction
      then in_fraction := true
      else if Char.is_digit c
      then (
        if !mantissa > (Int.max_value - 9) / 10 then invalid t;
        mantissa := (!mantissa * 10) + (Char.to_int c - Char.to_int '0');
        incr digits;
        if !in_fraction then incr fraction_digits)
      else invalid t;
      incr pos
    done;
    if !digits = 0 || !pos >= len - 1 then invalid t;
    incr pos;
    let exponent_negative =
      match String.unsafe_get t !pos with
      | '-' ->
        incr pos;
        true
      | '+' ->
        incr pos;
        false
      | _ -> false
    in
    if !pos >= len then invalid t;
    let exponent = ref 0 in
    while !pos < len do
      let c = String.unsafe_get t !pos in
      if (not (Char.is_digit c)) || !exponent > 1000 then invalid t;
      exponent := (!exponent * 10) + (Char.to_int c - Char.to_int '0');
      incr pos
    done;
    let exponent = if exponent_negative then - !exponent else !exponent in
    let shift = Md.Price.decimals - !fraction_digits + exponent in
    let units =
      if shift >= 0
      then (
        let units = ref !mantissa in
        for _ = 1 to shift do
          if !units > Int.max_value / 10 then invalid t;
          units := !units * 10
        done;
        !units)
      else (
        (* Digits past the 8th fractional one are truncated, as [of_string] does. *)
        let units = ref !mantissa in
        let i = ref 0 in
        while !i < -shift && !units > 0 do
          units := !units / 10;
          incr i
        done;
        !units)
    in
    if negative then -units else units
  ;;

  let to_price t =
    if is_exponent t then Md.Price.of_units (exponent_units t) else Md.Price.of_string t
  ;;

  let to_size t =
    if is_exponent t then Md.Size.of_units (exponent_units t) else Md.Size.of_string t
  ;;
end

module Kind = struct
  type t =
    | Snapshot
    | Update
  [@@deriving sexp_of, equal]
end

module Level = struct
  type t =
    { price : Number.t
    ; qty : Number.t
    }
  [@@deriving sexp_of, equal]
end

module Book = struct
  type t =
    { symbol : string
    ; bids : Level.t list
    ; asks : Level.t list
    ; checksum : int
    ; timestamp : Time_ns.t
    }
  [@@deriving sexp_of]
end

module Trade = struct
  type t =
    { symbol : string
    ; side : Md.Side.t
    ; price : Number.t
    ; qty : Number.t
    ; ord_type : string
    ; trade_id : int
    ; timestamp : Time_ns.t
    }
  [@@deriving sexp_of]
end

module Ticker = struct
  type t =
    { symbol : string
    ; bid : Number.t
    ; bid_qty : Number.t
    ; ask : Number.t
    ; ask_qty : Number.t
    ; timestamp : Time_ns.t
    }
  [@@deriving sexp_of]
end

module Ack = struct
  type t =
    { method_ : string
    ; success : bool
    ; channel : string option
    ; symbol : string option
    ; error : string option
    }
  [@@deriving sexp_of]
end

module Futures_ticker = struct
  type t =
    { product_id : string
    ; time : Time_ns.t
    ; relative_funding_rate : float option
    ; next_funding_rate_time : Time_ns.t option
    ; mark_price : Number.t option
    ; index : Number.t option
    }
  [@@deriving sexp_of]
end

type t =
  | Trade of Kind.t * Trade.t list
  | Ticker of Kind.t * Ticker.t list
  | Book of Kind.t * Book.t list
  | Heartbeat
  | Status
  | Ack of Ack.t
  | Futures_ticker of Futures_ticker.t
  | Futures_event of
      { event : string
      ; message : string option
      }
  | Unknown of string
[@@deriving sexp_of]

(* Field access over [Yojson.Raw.t]. Failures raise and are turned into [Error] by
   [of_string]. *)
module Json = struct
  let fail what json =
    raise_s [%message "unexpected json" what ~json:(Yojson.Raw.to_string json : string)]
  ;;

  let fields = function
    | `Assoc fields -> fields
    | json -> fail "expected an object" json
  ;;

  let find json name = List.Assoc.find (fields json) name ~equal:String.equal

  let member json name =
    match find json name with
    | Some v -> v
    | None -> fail ("missing field " ^ name) json
  ;;

  let string = function
    | `Stringlit lit as json ->
      (match Yojson.Safe.from_string lit with
       | `String s -> s
       | _ -> fail "expected a string" json)
    | json -> fail "expected a string" json
  ;;

  let number : Yojson.Raw.t -> Number.t = function
    | `Intlit s | `Floatlit s -> Number.of_string s
    | json -> fail "expected a number" json
  ;;

  let int json = Int.of_string (Number.to_string (number json))

  let bool = function
    | `Bool b -> b
    | json -> fail "expected a bool" json
  ;;

  let list f = function
    | `List items -> List.map items ~f
    | json -> fail "expected an array" json
  ;;

  let option f = function
    | None | Some `Null -> None
    | Some json -> Some (f json)
  ;;

  let time json =
    let s = string json in
    try Time_ns.of_string_with_utc_offset s with
    | _ -> fail "expected an RFC3339 time" json
  ;;

  let time_ms json = Time_ns.of_int_ns_since_epoch (int json * 1_000_000)
end

let kind json : Kind.t =
  match Json.string json with
  | "snapshot" -> Snapshot
  | "update" -> Update
  | _ -> Json.fail "unknown message type" json
;;

let level json : Level.t =
  { price = Json.number (Json.member json "price")
  ; qty = Json.number (Json.member json "qty")
  }
;;

let book json : Book.t =
  let m = Json.member json in
  { symbol = Json.string (m "symbol")
  ; bids = Json.list level (m "bids")
  ; asks = Json.list level (m "asks")
  ; checksum = Json.int (m "checksum")
  ; timestamp = Json.time (m "timestamp")
  }
;;

let side json : Md.Side.t =
  match Json.string json with
  | "buy" -> Buy
  | "sell" -> Sell
  | _ -> Json.fail "unknown side" json
;;

let trade json : Trade.t =
  let m = Json.member json in
  { symbol = Json.string (m "symbol")
  ; side = side (m "side")
  ; price = Json.number (m "price")
  ; qty = Json.number (m "qty")
  ; ord_type = Json.string (m "ord_type")
  ; trade_id = Json.int (m "trade_id")
  ; timestamp = Json.time (m "timestamp")
  }
;;

let ticker json : Ticker.t =
  let m = Json.member json in
  { symbol = Json.string (m "symbol")
  ; bid = Json.number (m "bid")
  ; bid_qty = Json.number (m "bid_qty")
  ; ask = Json.number (m "ask")
  ; ask_qty = Json.number (m "ask_qty")
  ; timestamp = Json.time (m "timestamp")
  }
;;

let ack json ~method_ : Ack.t =
  let result = Json.find json "result" in
  let in_result name =
    Option.bind result ~f:(fun r -> Json.option Json.string (Json.find r name))
  in
  { method_
  ; success = Option.value_map (Json.find json "success") ~default:true ~f:Json.bool
  ; channel = in_result "channel"
  ; symbol =
      (match in_result "symbol" with
       | Some _ as s -> s
       | None -> Json.option Json.string (Json.find json "symbol"))
  ; error = Json.option Json.string (Json.find json "error")
  }
;;

let futures_ticker json : Futures_ticker.t =
  let opt name f = Json.option f (Json.find json name) in
  { product_id = Json.string (Json.member json "product_id")
  ; time = Json.time_ms (Json.member json "time")
  ; relative_funding_rate =
      opt "relative_funding_rate" (fun j -> Number.to_float (Json.number j))
  ; next_funding_rate_time = opt "next_funding_rate_time" Json.time_ms
  ; mark_price = opt "markPrice" Json.number
  ; index = opt "index" Json.number
  }
;;

let decode json =
  match Json.find json "channel", Json.find json "method", Json.find json "feed" with
  | Some channel, _, _ ->
    let data f = Json.list f (Json.member json "data") in
    let kind () = kind (Json.member json "type") in
    (match Json.string channel with
     | "trade" ->
       let kind = kind () in
       Trade (kind, data trade)
     | "ticker" ->
       let kind = kind () in
       Ticker (kind, data ticker)
     | "book" ->
       let kind = kind () in
       Book (kind, data book)
     | "heartbeat" -> Heartbeat
     | "status" -> Status
     | other -> Unknown other)
  | None, Some method_, _ -> Ack (ack json ~method_:(Json.string method_))
  | None, None, Some feed ->
    (match Json.string feed, Json.find json "event" with
     | "ticker", None -> Futures_ticker (futures_ticker json)
     | _, Some event ->
       Futures_event
         { event = Json.string event
         ; message = Json.option Json.string (Json.find json "message")
         }
     | other, None -> Unknown other)
  | None, None, None ->
    (match Json.find json "event" with
     | Some event ->
       Futures_event
         { event = Json.string event
         ; message = Json.option Json.string (Json.find json "message")
         }
     | None -> Json.fail "unrecognised message" json)
;;

let of_string frame = Or_error.try_with (fun () -> decode (Yojson.Raw.from_string frame))
let strings symbols = `List (List.map symbols ~f:(fun s -> `String s))

let spot_subscribe ?(unsubscribe = false) ~channel symbols =
  let channel_params =
    match channel with
    | `Trade -> [ "channel", `String "trade"; "snapshot", `Bool false ]
    | `Bbo -> [ "channel", `String "ticker"; "event_trigger", `String "bbo" ]
    | `Book depth -> [ "channel", `String "book"; "depth", `Int depth ]
  in
  Yojson.Safe.to_string
    (`Assoc
      [ "method", `String (if unsubscribe then "unsubscribe" else "subscribe")
      ; "params", `Assoc (channel_params @ [ "symbol", strings symbols ])
      ])
;;

let futures_subscribe ~feed symbols =
  Yojson.Safe.to_string
    (`Assoc
      [ "event", `String "subscribe"
      ; "feed", `String feed
      ; "product_ids", strings symbols
      ])
;;
