open! Core
module Price = Market_data.Price

type t =
  { depth : int
  ; mutable synced : bool
  ; mutable bids : Wire.Level.t Price.Map.t
  ; mutable asks : Wire.Level.t Price.Map.t
  }

let create ~depth =
  { depth; synced = false; bids = Price.Map.empty; asks = Price.Map.empty }
;;

module Result = struct
  type t =
    | Applied
    | Waiting_for_snapshot
    | Checksum_mismatch of
        { expected : int
        ; computed : int
        }
  [@@deriving sexp_of, equal]
end

let reset t =
  t.synced <- false;
  t.bids <- Price.Map.empty;
  t.asks <- Price.Map.empty
;;

let is_synced t = t.synced
let bids t = Map.data t.bids |> List.rev
let asks t = Map.data t.asks

let set side (level : Wire.Level.t) =
  let price = Wire.Number.to_price level.price in
  if Market_data.Size.is_zero (Wire.Number.to_size level.qty)
  then Map.remove side price
  else Map.set side ~key:price ~data:level
;;

let truncate t =
  let drop_beyond map ~keep =
    if Map.length map <= t.depth
    then map
    else Map.filter_keys map ~f:(fun price -> Set.mem keep price)
  in
  let best_bids = List.take (Map.keys t.bids |> List.rev) t.depth |> Price.Set.of_list in
  let best_asks = List.take (Map.keys t.asks) t.depth |> Price.Set.of_list in
  t.bids <- drop_beyond t.bids ~keep:best_bids;
  t.asks <- drop_beyond t.asks ~keep:best_asks
;;

let checksum t = Checksum.of_levels ~bids:(bids t) ~asks:(asks t)

let apply t (kind : Wire.Kind.t) (book : Wire.Book.t) : Result.t =
  match kind, t.synced with
  | Update, false -> Waiting_for_snapshot
  | Snapshot, _ | Update, true ->
    (match kind with
     | Snapshot -> reset t
     | Update -> ());
    t.bids <- List.fold book.bids ~init:t.bids ~f:set;
    t.asks <- List.fold book.asks ~init:t.asks ~f:set;
    truncate t;
    let computed = checksum t in
    if computed = book.checksum
    then (
      t.synced <- true;
      Applied)
    else (
      reset t;
      Checksum_mismatch { expected = book.checksum; computed })
;;
