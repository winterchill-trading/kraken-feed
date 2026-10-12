(** The spot v2 book checksum: CRC32 over the top 10 asks (ascending) then the top 10 bids
    (descending), each level written as its price then its quantity with the decimal point
    and leading zeros removed. *)

open! Core

(** IEEE CRC32 of a string, as a non-negative int. *)
val crc32 : string -> int

(** ["0.00100000"] becomes ["100000"], ["45285.2"] becomes ["452852"]. *)
val format_number : Wire.Number.t -> string

(** [bids] best (highest) first, [asks] best (lowest) first; only the first 10 of each
    count. *)
val of_levels : bids:Wire.Level.t list -> asks:Wire.Level.t list -> int
