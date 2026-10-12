(** A live {!Market_data.Feed.t} over Kraken's public websockets. Read-only, no
    credentials.

    Each requested stream gets its own {!Venue_net.Ws_client} connection, so every frame
    is known to belong to one stream before it is parsed:

    - [Trades]: spot v2 [trade];
    - [Bbo]: spot v2 [ticker] with [event_trigger = bbo];
    - [L2]: spot v2 [book] at [l2_depth] (default 10; one of 10, 25, 100, 500, 1000). A
      checksum mismatch unsubscribes and subscribes the symbol again, which makes the
      venue send a new snapshot;
    - [Funding]: futures v1 [ticker].

    [symbols] may be spot ([BTC/USD]) or futures ([PF_XBTUSD]) names; each stream maps
    them with {!Symbols} to the API it uses. See {!Normalizer} for the event fields.

    [recv_ts] is [Time_ns.now ()] when the frame is received. [on_raw] gets that frame
    unparsed, first, including acks and heartbeats. Undecodable frames are logged, counted
    in {!stats} and skipped.

    Disconnects are handled by {!Venue_net.Ws_client}: it reconnects with exponential
    backoff, and the feed then resubscribes; books are cleared so the snapshot that
    follows a resubscription is emitted as a fresh [Snapshot]. Spot connections send an
    application ping every 30s, futures connections a websocket ping frame (the futures
    API closes connections idle for 60s). Pipes of streams that were not requested stay
    empty until [close]. Writes do not wait for readers, so consumers should keep up. *)

open! Core
open Async

(** Raises if a first connection fails, if [streams] contains [Private], or on a symbol
    {!Symbols} cannot map. *)
val create
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?l2_depth:int
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> Market_data.Feed.t Deferred.t

type t

(** Like {!create}, keeping the handle for {!stats}. *)
val start
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?l2_depth:int
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> t Deferred.t

val feed : t -> Market_data.Feed.t

module Stats : sig
  type t =
    { frames : int (** websocket text frames received, acks and heartbeats included *)
    ; parse_errors : int (** frames that did not decode and were dropped *)
    ; reconnects : int (** successful reconnections, summed over the connections *)
    }
  [@@deriving sexp_of]
end

val stats : t -> Stats.t

(** The subscribe request for a stream, with symbols already mapped. *)
val subscribe_request
  :  ?unsubscribe:bool
  -> ?l2_depth:int
  -> Market_data.Stream.t
  -> string list
  -> string
