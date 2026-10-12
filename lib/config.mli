(** Websocket endpoints. Spot v2 carries trades, BBO and the L2 book; the futures API
    carries funding, mark and index of perpetuals. *)

open! Core

type t =
  { spot_url : Uri.t
  ; futures_url : Uri.t
  }
[@@deriving sexp_of]

(** [wss://ws.kraken.com/v2] and [wss://futures.kraken.com/ws/v1]. *)
val mainnet : t

(** {!mainnet} with either URL replaced, e.g. by a local mock. *)
val create : ?spot_url:Uri.t -> ?futures_url:Uri.t -> unit -> t
