open! Core

type t = Normalizer.t

let venue = Market_data.Venue.Kraken
let create () = Normalizer.create ()

let frame t ~recv_ts payload =
  Or_error.map (Normalizer.frame t ~recv_ts payload) ~f:(fun (o : Normalizer.Output.t) ->
    o.events)
;;

let disconnect = Normalizer.reset
