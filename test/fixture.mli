(** A trimmed minute of mainnet frames recorded by market-recorder on 2026-10-12, in its
    raw layout under [fixtures/raw/kraken/<stream>/<symbol>/2026/10/12/HH-MM.ndjson]
    ([<recv_ts> <frame>] per line). The first file of each stream starts at the
    subscription; the second is cut to keep the fixtures small. *)

open! Core

(** [fixtures], the [data_dir] of the recording. *)
val data_dir : string

val date : Date.t
val streams : Market_data.Stream.t list

(** Frames of [stream] in recording order, with their receive times. *)
val frames : Market_data.Stream.t -> (Time_ns.t * string) list
