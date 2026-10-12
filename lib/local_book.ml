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
    | Applied of
        { truncated_bids : Wire.Level.t list
        ; truncated_asks : Wire.Level.t list
        }
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

(* Drops the levels beyond [depth], counted from the best price, and returns them. *)
let truncate t =
  let drop_bids = List.drop (bids t) t.depth
  and drop_asks = List.drop (asks t) t.depth in
  let remove map dropped =
    List.fold dropped ~init:map ~f:(fun map (level : Wire.Level.t) ->
      Map.remove map (Wire.Number.to_price level.price))
  in
  t.bids <- remove t.bids drop_bids;
  t.asks <- remove t.asks drop_asks;
  drop_bids, drop_asks
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
    let truncated_bids, truncated_asks = truncate t in
    let computed = checksum t in
    if computed = book.checksum
    then (
      t.synced <- true;
      Applied { truncated_bids; truncated_asks })
    else (
      reset t;
      Checksum_mismatch { expected = book.checksum; computed })
;;
