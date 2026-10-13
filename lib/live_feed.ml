open! Core
open Async
module Md = Market_data
module Ws_client = Venue_net.Ws_client

let valid_depths = [ 10; 25; 100; 500; 1000 ]

let subscribe_request ?unsubscribe ?(l2_depth = 10) (stream : Md.Stream.t) symbols =
  match stream with
  | Trades -> Wire.spot_subscribe ?unsubscribe ~channel:`Trade symbols
  | Bbo -> Wire.spot_subscribe ?unsubscribe ~channel:`Bbo symbols
  | L2 -> Wire.spot_subscribe ?unsubscribe ~channel:(`Book l2_depth) symbols
  | Funding ->
    (match unsubscribe with
     | Some true ->
       raise_s [%message "Live_feed: futures ticker resubscription is not used"]
     | Some false | None -> Wire.futures_subscribe ~feed:"ticker" symbols)
  | Private -> raise_s [%message "Live_feed: no public channel for the private stream"]
;;

let ping_interval = Time_ns.Span.of_sec 30.

module Stats = struct
  type t =
    { frames : int
    ; parse_errors : int
    ; reconnects : int
    }
  [@@deriving sexp_of]
end

type counters =
  { mutable frames : int
  ; mutable parse_errors : int
  }

type t =
  { feed : Md.Feed.With_gaps.t
  ; counters : counters
  ; sockets : Ws_client.t list
  }

let feed t = Md.Feed.With_gaps.to_feed t.feed
let feed_with_gaps t = t.feed

let stats t : Stats.t =
  { frames = t.counters.frames
  ; parse_errors = t.counters.parse_errors
  ; reconnects = List.sum (module Int) t.sockets ~f:Ws_client.reconnects
  }
;;

let start_with
  ~via_messages
  ?on_raw
  ?(l2_depth = 10)
  ?(time_source = Time_source.wall_clock ())
  (config : Config.t)
  ~symbols
  ~streams
  =
  let streams = List.dedup_and_sort streams ~compare:Md.Stream.compare in
  if List.mem streams Private ~equal:Md.Stream.equal
  then raise_s [%message "Live_feed.create: the private stream is not a market feed"];
  if not (List.mem valid_depths l2_depth ~equal:Int.equal)
  then raise_s [%message "Live_feed.create: unsupported book depth" (l2_depth : int)];
  let trades_r, trades_w = Pipe.create () in
  let bbo_r, bbo_w = Pipe.create () in
  let l2_r, l2_w = Pipe.create () in
  let funding_r, funding_w = Pipe.create () in
  let gaps_r, gaps_w = Pipe.create () in
  let gap ~recv_ts ~stream ?instrument () =
    Pipe.write_without_pushback_if_open
      gaps_w
      { Md.Gap.recv_ts
      ; venue = Kraken
      ; instrument
      ; stream = Some stream
      ; reason = Resync
      }
  in
  let counters = { frames = 0; parse_errors = 0 } in
  let emit : Md.Event.t -> unit = function
    | Trade x -> Pipe.write_without_pushback_if_open trades_w x
    | Bbo x -> Pipe.write_without_pushback_if_open bbo_w x
    | L2 x -> Pipe.write_without_pushback_if_open l2_w x
    | Funding x -> Pipe.write_without_pushback_if_open funding_w x
  in
  let connect (stream : Md.Stream.t) =
    let stream_name = Md.Stream.to_string stream in
    let url, ping, symbols =
      match stream with
      | Funding ->
        config.futures_url, `Frame ping_interval, List.map symbols ~f:Symbols.futures
      | Trades | Bbo | L2 | Private ->
        ( config.spot_url
        , `Text ({|{"method":"ping"}|}, ping_interval)
        , List.map symbols ~f:Symbols.spot )
    in
    let symbols = List.dedup_and_sort symbols ~compare:String.compare in
    let normalizer = Normalizer.create ~l2_depth () in
    (* Reconnects already reported. [on_connect] runs before the new connection's frames
       are delivered; the frame handler checks too (frames read from [messages] arrive in
       a later job), so whichever runs first reports the gap and clears the books, and the
       gap always precedes the new connection's events. *)
    let reported = ref 0 in
    let report_reconnect ws ~recv_ts =
      let reconnects = Ws_client.reconnects ws in
      if reconnects > !reported
      then (
        reported := reconnects;
        Normalizer.reset normalizer;
        gap ~recv_ts ~stream ())
    in
    (* The client frames arrive on, set by [on_connect], which runs before the first frame
       of every connection. *)
    let current = ref None in
    let on_connect ws =
      current := Some ws;
      if Ws_client.reconnects ws > 0
      then (
        Log.Global.info "kraken feed: %s reconnected, resubscribing" stream_name;
        report_reconnect ws ~recv_ts:(Time_source.now time_source));
      Ws_client.send ws (subscribe_request ~l2_depth stream symbols)
    in
    let resubscribe ws symbol =
      let%bind () =
        Ws_client.send
          ws
          (subscribe_request ~unsubscribe:true ~l2_depth stream [ symbol ])
      in
      Ws_client.send ws (subscribe_request ~l2_depth stream [ symbol ])
    in
    let handle frame =
      match !current with
      | None -> ()
      | Some ws ->
        let recv_ts = Time_source.now time_source in
        counters.frames <- counters.frames + 1;
        report_reconnect ws ~recv_ts;
        Option.iter on_raw ~f:(fun on_raw -> on_raw ~stream ~recv_ts frame);
        (match Normalizer.frame normalizer ~recv_ts frame with
         | Error error ->
           counters.parse_errors <- counters.parse_errors + 1;
           Log.Global.error_s
             [%message
               "kraken feed: cannot parse frame"
                 ~stream:stream_name
                 (frame : string)
                 (error : Error.t)]
         | Ok { events; resubscribe = symbols } ->
           List.iter events ~f:emit;
           List.iter symbols ~f:(fun symbol ->
             gap ~recv_ts ~stream ~instrument:(Normalizer.instrument symbol) ();
             don't_wait_for (resubscribe ws symbol)))
    in
    (* [on_message] hands each frame over with no pipe in between; reading [messages] one
       frame at a time cost about 13 words per frame more (see venue-net's README). The
       pipe path is kept for [For_testing.start_via_messages]. *)
    let%map ws =
      Ws_client.connect
        ~time_source
        ~ping
        ~on_connect
        ?on_message:(if via_messages then None else Some handle)
        ~log_name:("kraken " ^ stream_name)
        ~url
        ()
      >>| Or_error.ok_exn
    in
    if via_messages
    then don't_wait_for (Pipe.iter_without_pushback (Ws_client.messages ws) ~f:handle);
    ws
  in
  let opened = ref [] in
  let close_all () = Deferred.List.iter !opened ~how:`Parallel ~f:Ws_client.close in
  let%bind () =
    match%bind
      Monitor.try_with (fun () ->
        Deferred.List.iter streams ~how:`Sequential ~f:(fun stream ->
          let%map ws = connect stream in
          opened := ws :: !opened))
    with
    | Ok () -> return ()
    | Error exn ->
      let%map () = close_all () in
      raise exn
  in
  let closed =
    Lazy_deferred.create (fun () ->
      let%map () = close_all () in
      Pipe.close trades_w;
      Pipe.close bbo_w;
      Pipe.close l2_w;
      Pipe.close funding_w;
      Pipe.close gaps_w)
  in
  let feed =
    (module struct
      let trades = trades_r
      let bbo = bbo_r
      let l2 = l2_r
      let funding = funding_r
      let gaps = gaps_r
      let close () = Lazy_deferred.force_exn closed
    end : Md.Feed.With_gaps.S)
  in
  return { feed; counters; sockets = !opened }
;;

let start = start_with ~via_messages:false

module For_testing = struct
  let start_via_messages = start_with ~via_messages:true
end

let create ?on_raw ?l2_depth ?time_source config ~symbols ~streams =
  let%map t = start ?on_raw ?l2_depth ?time_source config ~symbols ~streams in
  feed t
;;
