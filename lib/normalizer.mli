(** Kraken frames to normalized {!Market_data} events. Pure apart from logging; the Async
    driver is {!Live_feed}.

    - spot [trade]: one {!Market_data.Trade.t} per print, [exch_ts] the trade time,
      [trade_id] the per-pair trade sequence number;
    - spot [ticker] (BBO trigger): a {!Market_data.Bbo.t} per message, [exch_ts] the
      ticker time;
    - spot [book]: kept in a {!Local_book} per symbol. A snapshot becomes an
      {!Market_data.L2_update.t} [Snapshot] (levels best first); an update becomes a
      [Delta] with the levels as sent plus a zero-size level for every level pushed beyond
      the subscribed depth. Updates before the first snapshot are dropped. A checksum
      mismatch clears the book and asks for a resubscription;
    - futures [ticker]: a {!Market_data.Funding.t} when the relative funding rate, next
      funding time, mark or index price changed since the last one for the product ([rate]
      is [relative_funding_rate], 0 when absent).

    Instruments are [kraken:<symbol>] with the venue's own symbol ([BTC/USD] on spot,
    [PF_XBTUSD] on futures). *)

open! Core

type t

(** [l2_depth] (default 10) is the depth the book channel is subscribed with. *)
val create : ?l2_depth:int -> unit -> t

val instrument : string -> Market_data.Instrument.t

module Output : sig
  type t =
    { events : Market_data.Event.t list
    ; resubscribe : string list (** spot book symbols whose checksum failed *)
    }
  [@@deriving sexp_of]

  val empty : t
end

val message : t -> recv_ts:Time_ns.t -> Wire.t -> Output.t

(** Decodes then {!message}. *)
val frame : t -> recv_ts:Time_ns.t -> string -> Output.t Or_error.t

(** Clears every book, e.g. after a reconnect; each waits for a new snapshot. *)
val reset : t -> unit
