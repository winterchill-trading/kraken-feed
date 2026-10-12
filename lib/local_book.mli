(** The spot v2 order book of one symbol, kept to check every message's checksum.

    Levels keep the venue's number literals, which the checksum is computed over. *)

open! Core

type t

(** An empty book that waits for a snapshot. [depth] is the subscribed depth: levels
    beyond it are dropped after every message, as the venue does not send removals for
    them. *)
val create : depth:int -> t

module Result : sig
  type t =
    | Applied
    | Waiting_for_snapshot (** an update before the first snapshot; ignored *)
    | Checksum_mismatch of
        { expected : int
        ; computed : int
        } (** the book is cleared and waits for a new snapshot *)
  [@@deriving sexp_of, equal]
end

val apply : t -> Wire.Kind.t -> Wire.Book.t -> Result.t

(** Clears the book; updates are ignored until the next snapshot. *)
val reset : t -> unit

val is_synced : t -> bool

(** Best first. *)
val bids : t -> Wire.Level.t list

val asks : t -> Wire.Level.t list
val checksum : t -> int
