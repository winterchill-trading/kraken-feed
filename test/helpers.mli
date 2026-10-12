(** Printing for expect tests. Timestamps print in UTC so the output is the same on every
    machine. *)

open! Core

val utc : Time_ns.t -> string
val sexp_of_event : Market_data.Event.t -> Sexp.t
val print_output : Kraken_feed.Normalizer.Output.t Or_error.t -> unit

(** A fixed receive time for tests. *)
val recv_ts : Time_ns.t

(** [approx ~expected ~tolerance actual] prints as [expected+-tolerance] when [actual] is
    within [tolerance] of [expected], and as [actual] otherwise, so an expect test can pin
    an allocation count that differs by a few words between macOS and Linux. *)
val approx : expected:int -> tolerance:int -> int -> Sexp.t
