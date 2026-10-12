open! Core
module Md = Market_data

let instrument symbol = Md.Instrument.create Kraken symbol

module Output = struct
  type t =
    { events : Md.Event.t list
    ; resubscribe : string list
    }
  [@@deriving sexp_of]

  let empty = { events = []; resubscribe = [] }
  let events events = { events; resubscribe = [] }
end

module Funding_key = struct
  type t =
    { rate : float
    ; next_funding_time : Time_ns.t
    ; mark : Md.Price.t
    ; index : Md.Price.t
    }
  [@@deriving equal]
end

type t =
  { l2_depth : int
  ; books : Local_book.t String.Table.t
  ; funding : Funding_key.t String.Table.t (** last emitted, by product *)
  }

let create ?(l2_depth = 10) () =
  { l2_depth; books = String.Table.create (); funding = String.Table.create () }
;;

let reset t = Hashtbl.iter t.books ~f:Local_book.reset

let trade ~recv_ts (trade : Wire.Trade.t) =
  Md.Event.Trade
    { instrument = instrument trade.symbol
    ; exch_ts = trade.timestamp
    ; recv_ts
    ; price = Wire.Number.to_price trade.price
    ; size = Wire.Number.to_size trade.qty
    ; side = trade.side
    ; trade_id = Int.to_string trade.trade_id
    }
;;

let bbo ~recv_ts (ticker : Wire.Ticker.t) =
  Md.Event.Bbo
    { instrument = instrument ticker.symbol
    ; exch_ts = ticker.timestamp
    ; recv_ts
    ; bid_price = Wire.Number.to_price ticker.bid
    ; bid_size = Wire.Number.to_size ticker.bid_qty
    ; ask_price = Wire.Number.to_price ticker.ask
    ; ask_size = Wire.Number.to_size ticker.ask_qty
    }
;;

let level ({ price; qty } : Wire.Level.t) : Md.L2_update.Level.t =
  { price = Wire.Number.to_price price; size = Wire.Number.to_size qty }
;;

let removed ({ price; qty = _ } : Wire.Level.t) : Md.L2_update.Level.t =
  { price = Wire.Number.to_price price; size = Md.Size.zero }
;;

let book t ~recv_ts (kind : Wire.Kind.t) (msg : Wire.Book.t) : Output.t =
  let local =
    Hashtbl.find_or_add t.books msg.symbol ~default:(fun () ->
      Local_book.create ~depth:t.l2_depth)
  in
  match Local_book.apply local kind msg with
  | Waiting_for_snapshot -> Output.empty
  | Checksum_mismatch { expected; computed } ->
    Async.Log.Global.info_s
      [%message
        "kraken feed: book checksum mismatch, resubscribing"
          ~symbol:msg.symbol
          (expected : int)
          (computed : int)];
    { events = []; resubscribe = [ msg.symbol ] }
  | Applied { truncated_bids; truncated_asks } ->
    let (l2_kind : Md.L2_update.Kind.t), bids, asks =
      match kind with
      | Snapshot ->
        ( Snapshot
        , List.map (Local_book.bids local) ~f:level
        , List.map (Local_book.asks local) ~f:level )
      | Update ->
        ( Delta
        , List.map msg.bids ~f:level @ List.map truncated_bids ~f:removed
        , List.map msg.asks ~f:level @ List.map truncated_asks ~f:removed )
    in
    Output.events
      [ Md.Event.L2
          { instrument = instrument msg.symbol
          ; exch_ts = msg.timestamp
          ; recv_ts
          ; kind = l2_kind
          ; bids
          ; asks
          }
      ]
;;

let funding t ~recv_ts (ticker : Wire.Futures_ticker.t) =
  match ticker with
  | { next_funding_rate_time = Some next_funding_time
    ; mark_price = Some mark
    ; index = Some index
    ; _
    } ->
    let key =
      { Funding_key.rate = Option.value ticker.relative_funding_rate ~default:0.
      ; next_funding_time
      ; mark = Wire.Number.to_price mark
      ; index = Wire.Number.to_price index
      }
    in
    (match Hashtbl.find t.funding ticker.product_id with
     | Some last when Funding_key.equal last key -> []
     | Some _ | None ->
       Hashtbl.set t.funding ~key:ticker.product_id ~data:key;
       [ Md.Event.Funding
           { instrument = instrument ticker.product_id
           ; exch_ts = ticker.time
           ; recv_ts
           ; rate = key.rate
           ; next_funding_time
           ; mark_price = key.mark
           ; index_price = key.index
           }
       ])
  | _ -> []
;;

let message t ~recv_ts (message : Wire.t) : Output.t =
  match message with
  | Trade (_, trades) -> Output.events (List.map trades ~f:(trade ~recv_ts))
  | Ticker (_, tickers) -> Output.events (List.map tickers ~f:(bbo ~recv_ts))
  | Book (kind, books) ->
    List.fold books ~init:Output.empty ~f:(fun acc msg ->
      let out = book t ~recv_ts kind msg in
      { events = acc.events @ out.events
      ; resubscribe = acc.resubscribe @ out.resubscribe
      })
  | Futures_ticker ticker -> Output.events (funding t ~recv_ts ticker)
  | Ack { success = false; method_; channel; symbol; error } ->
    Async.Log.Global.error_s
      [%message
        "kraken feed: request rejected"
          method_
          (channel : string option)
          (symbol : string option)
          (error : string option)];
    Output.empty
  | Futures_event { event = ("error" | "alert") as event; message } ->
    Async.Log.Global.error_s
      [%message "kraken feed: futures" event (message : string option)];
    Output.empty
  | Ack _ | Heartbeat | Status | Futures_event _ | Unknown _ -> Output.empty
;;

let frame t ~recv_ts frame =
  let%bind.Or_error decoded = Wire.of_string frame in
  Or_error.try_with (fun () -> message t ~recv_ts decoded)
;;
