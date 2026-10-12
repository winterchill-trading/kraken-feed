(** Kraken names one market differently on its two APIs: spot v2 uses [BTC/USD], futures
    uses [PF_XBTUSD] for the linear perpetual. These helpers map between the two so one
    [-symbol] can drive every stream. *)

open! Core

(** ["BTC/USD"] is ["PF_XBTUSD"] ([BTC] is [XBT] on futures); futures symbols are returned
    unchanged. Raises on anything else. *)
val futures : string -> string

(** ["PF_XBTUSD"] is ["BTC/USD"]; spot symbols are returned unchanged. Raises on a futures
    symbol that is not a [PF_] perpetual with a 3-letter quote. *)
val spot : string -> string

val is_futures : string -> bool
