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

let create ?on_raw ?(l2_depth = 10) (config : Config.t) ~symbols ~streams =
  let streams = List.dedup_and_sort streams ~compare:Md.Stream.compare in
  if List.mem streams Private ~equal:Md.Stream.equal
  then raise_s [%message "Live_feed.create: the private stream is not a market feed"];
  if not (List.mem valid_depths l2_depth ~equal:Int.equal)
  then raise_s [%message "Live_feed.create: unsupported book depth" (l2_depth : int)];
  let trades_r, trades_w = Pipe.create () in
  let bbo_r, bbo_w = Pipe.create () in
  let l2_r, l2_w = Pipe.create () in
  let funding_r, funding_w = Pipe.create () in
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
    let on_connect ws =
      if Ws_client.reconnects ws > 0
      then (
        Log.Global.info "kraken feed: %s reconnected, resubscribing" stream_name;
        Normalizer.reset normalizer);
      Ws_client.send ws (subscribe_request ~l2_depth stream symbols)
    in
    let%map ws =
      Ws_client.connect ~ping ~on_connect ~log_name:("kraken " ^ stream_name) ~url ()
      >>| Or_error.ok_exn
    in
    let resubscribe symbol =
      let%bind () =
        Ws_client.send
          ws
          (subscribe_request ~unsubscribe:true ~l2_depth stream [ symbol ])
      in
      Ws_client.send ws (subscribe_request ~l2_depth stream [ symbol ])
    in
    don't_wait_for
      (Pipe.iter_without_pushback (Ws_client.messages ws) ~f:(fun frame ->
         let recv_ts = Time_ns.now () in
         Option.iter on_raw ~f:(fun on_raw -> on_raw ~stream ~recv_ts frame);
         match Normalizer.frame normalizer ~recv_ts frame with
         | Error error ->
           Log.Global.error_s
             [%message
               "kraken feed: cannot parse frame"
                 ~stream:stream_name
                 (frame : string)
                 (error : Error.t)]
         | Ok { events; resubscribe = symbols } ->
           List.iter events ~f:emit;
           List.iter symbols ~f:(fun symbol -> don't_wait_for (resubscribe symbol))));
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
      Pipe.close funding_w)
  in
  return
    (module struct
      let trades = trades_r
      let bbo = bbo_r
      let l2 = l2_r
      let funding = funding_r
      let close () = Lazy_deferred.force_exn closed
    end : Md.Feed.S)
;;
