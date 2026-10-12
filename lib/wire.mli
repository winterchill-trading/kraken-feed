(** Decoded Kraken websocket frames: the spot v2 [trade], [ticker] and [book] channels and
    the futures v1 [ticker] feed.

    Frames are parsed with [Yojson.Raw] so number literals keep the exact digits the venue
    printed: the book checksum is computed over them, and decimals never pass through a
    float. *)

open! Core

(** A JSON number literal as sent, e.g. ["82690.0"], ["0.00005100"], ["9.6e-6"]. *)
module Number : sig
  type t = private string [@@deriving sexp_of, equal]

  val of_string : string -> t
  val to_string : t -> string

  (** Exact for plain decimals (digits past the 8th fractional one are truncated);
      exponent forms go through a float. *)
  val to_price : t -> Market_data.Price.t

  val to_size : t -> Market_data.Size.t
  val to_float : t -> float
end

module Kind : sig
  type t =
    | Snapshot
    | Update
  [@@deriving sexp_of, equal]
end

module Level : sig
  type t =
    { price : Number.t
    ; qty : Number.t
    }
  [@@deriving sexp_of, equal]
end

module Book : sig
  type t =
    { symbol : string
    ; bids : Level.t list
    ; asks : Level.t list
    ; checksum : int (** CRC32 of the top 10 levels after applying this message *)
    ; timestamp : Time_ns.t
    }
  [@@deriving sexp_of]
end

module Trade : sig
  type t =
    { symbol : string
    ; side : Market_data.Side.t (** taker side *)
    ; price : Number.t
    ; qty : Number.t
    ; ord_type : string
    ; trade_id : int
    ; timestamp : Time_ns.t
    }
  [@@deriving sexp_of]
end

module Ticker : sig
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

(** Response to a [subscribe], [unsubscribe] or [ping] request. *)
module Ack : sig
  type t =
    { method_ : string
    ; success : bool (** [true] for a pong *)
    ; channel : string option
    ; symbol : string option
    ; error : string option
    }
  [@@deriving sexp_of]
end

module Futures_ticker : sig
  type t =
    { product_id : string
    ; time : Time_ns.t
    ; relative_funding_rate : float option
    (** per funding period, as a fraction of the spot price *)
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
  | Status (** spot connection status *)
  | Ack of Ack.t
  | Futures_ticker of Futures_ticker.t
  | Futures_event of
      { event : string (** [info], [subscribed], [error], ... *)
      ; message : string option
      }
  | Unknown of string (** a well-formed frame of a channel or feed not used here *)
[@@deriving sexp_of]

(** [Error] for invalid JSON or a known message with missing or ill-typed fields. *)
val of_string : string -> t Or_error.t

(** Subscription requests. *)

val spot_subscribe
  :  ?unsubscribe:bool
  -> channel:[ `Trade | `Bbo | `Book of int ]
  -> string list
  -> string

val futures_subscribe : feed:string -> string list -> string
