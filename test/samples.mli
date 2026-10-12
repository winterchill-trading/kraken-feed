(** Frames captured from the live API, shared by the tests. *)

(** BTC/USD book snapshot at depth 10. *)
val snapshot : string

(** The two book updates that followed {!snapshot}. *)
val update1 : string

val update2 : string
