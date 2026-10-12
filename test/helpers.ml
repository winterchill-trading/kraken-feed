open! Core
module Md = Market_data

let utc time = Time_ns.to_string_iso8601_basic time ~zone:Time_float.Zone.utc
let recv_ts = Time_ns.of_string_with_utc_offset "2026-10-12T12:00:00Z"

let sexp_of_levels levels =
  List.map levels ~f:(fun ({ price; size } : Md.L2_update.Level.t) ->
    [%sexp (Md.Price.to_string price : string), (Md.Size.to_string size : string)])
  |> Sexp.List
;;

let sexp_of_event (event : Md.Event.t) =
  match event with
  | Trade t ->
    [%sexp
      Trade
        { instrument = (Md.Instrument.to_string t.instrument : string)
        ; exch_ts = (utc t.exch_ts : string)
        ; price = (Md.Price.to_string t.price : string)
        ; size = (Md.Size.to_string t.size : string)
        ; side = (t.side : Md.Side.t)
        ; trade_id : string = t.trade_id
        }]
  | Bbo b ->
    [%sexp
      Bbo
        { instrument = (Md.Instrument.to_string b.instrument : string)
        ; exch_ts = (utc b.exch_ts : string)
        ; bid = (Md.Price.to_string b.bid_price : string)
        ; bid_size = (Md.Size.to_string b.bid_size : string)
        ; ask = (Md.Price.to_string b.ask_price : string)
        ; ask_size = (Md.Size.to_string b.ask_size : string)
        }]
  | L2 l ->
    [%sexp
      L2
        { instrument = (Md.Instrument.to_string l.instrument : string)
        ; exch_ts = (utc l.exch_ts : string)
        ; kind = (l.kind : Md.L2_update.Kind.t)
        ; bids = (sexp_of_levels l.bids : Sexp.t)
        ; asks = (sexp_of_levels l.asks : Sexp.t)
        }]
  | Funding f ->
    [%sexp
      Funding
        { instrument = (Md.Instrument.to_string f.instrument : string)
        ; exch_ts = (utc f.exch_ts : string)
        ; rate : float = f.rate
        ; next_funding_time = (utc f.next_funding_time : string)
        ; mark = (Md.Price.to_string f.mark_price : string)
        ; index = (Md.Price.to_string f.index_price : string)
        }]
;;

let print_output (output : Kraken_feed.Normalizer.Output.t Or_error.t) =
  match output with
  | Error error -> print_s [%sexp Error (error : Error.t)]
  | Ok { events; resubscribe } ->
    List.iter events ~f:(fun event -> print_s (sexp_of_event event));
    if not (List.is_empty resubscribe)
    then print_s [%sexp Resubscribe (resubscribe : string list)]
;;
