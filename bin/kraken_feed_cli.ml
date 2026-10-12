open! Core
open Async
module Md = Market_data

let streams_arg =
  Command.Arg_type.create (fun s ->
    String.split s ~on:',' |> List.map ~f:String.strip |> List.map ~f:Md.Stream.of_string)
;;

let feed_command =
  Command.async
    ~summary:"Print normalized Kraken market data as sexps"
    (let%map_open.Command symbols =
       flag
         "symbol"
         (one_or_more_as_list string)
         ~doc:"SYM spot pair (BTC/USD) or perpetual (PF_XBTUSD); repeatable"
     and streams =
       flag
         "streams"
         (optional_with_default Md.Stream.[ Trades; Bbo; L2; Funding ] streams_arg)
         ~doc:"LIST comma separated: trades,bbo,l2,funding (default all)"
     and count = flag "count" (optional int) ~doc:"N stop after N events"
     and l2_depth =
       flag "l2-depth" (optional_with_default 10 int) ~doc:"N book depth (default 10)"
     and raw = flag "raw" no_arg ~doc:" also print every raw frame"
     and spot_url = flag "spot-url" (optional string) ~doc:"URL spot websocket"
     and futures_url =
       flag "futures-url" (optional string) ~doc:"URL futures websocket"
     in
     fun () ->
       let config =
         Kraken_feed.Config.create
           ?spot_url:(Option.map spot_url ~f:Uri.of_string)
           ?futures_url:(Option.map futures_url ~f:Uri.of_string)
           ()
       in
       let on_raw =
         Option.some_if raw (fun ~stream ~recv_ts:_ frame ->
           print_endline (sprintf "raw %s %s" (Md.Stream.to_string stream) frame))
       in
       let%bind (module Feed) =
         Kraken_feed.Live_feed.create ?on_raw ~l2_depth config ~symbols ~streams
       in
       let seen = ref 0 in
       let finished = Ivar.create () in
       let print sexp =
         if not (Ivar.is_full finished)
         then (
           print_s sexp;
           incr seen;
           match count with
           | Some n when !seen >= n -> Ivar.fill_if_empty finished ()
           | Some _ | None -> ())
       in
       let iter pipe sexp_of =
         Pipe.iter_without_pushback pipe ~f:(fun x -> print (sexp_of x))
       in
       let all_closed =
         Deferred.all_unit
           [ iter Feed.trades (fun x -> [%sexp Trade (x : Md.Trade.t)])
           ; iter Feed.bbo (fun x -> [%sexp Bbo (x : Md.Bbo.t)])
           ; iter Feed.l2 (fun x -> [%sexp L2 (x : Md.L2_update.t)])
           ; iter Feed.funding (fun x -> [%sexp Funding (x : Md.Funding.t)])
           ]
       in
       let%bind () = Deferred.any [ Ivar.read finished; all_closed ] in
       Feed.close ())
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Read-only public Kraken market data"
       [ "feed", feed_command ])
;;
