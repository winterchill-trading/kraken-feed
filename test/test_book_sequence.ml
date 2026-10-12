open! Core
open Kraken_feed

let snapshot = Samples.snapshot
let update1 = Samples.update1
let update2 = Samples.update2

let feed normalizer frame =
  Helpers.print_output (Normalizer.frame normalizer ~recv_ts:Helpers.recv_ts frame)
;;

let%expect_test "live snapshot then updates, with a level truncated past depth 10" =
  let normalizer = Normalizer.create ~l2_depth:10 () in
  feed normalizer snapshot;
  [%expect
    {|
    (L2
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:21.094243000Z)
      (kind Snapshot)
      (bids
       ((82689 0.00055351) (82688.7 0.000051) (82687.4 0.00090703)
        (82684.5 0.000051) (82683.8 0.00012081) (82683.7 0.22354849)
        (82683.6 3.02357136) (82681.5 3.02364775) (82680.4 0.000051)
        (82676.3 0.000051)))
      (asks
       ((82689.1 1.23752222) (82689.8 0.14580116) (82690 1.89824541)
        (82690.1 3.02333839) (82690.2 0.02418666) (82690.7 0.0055)
        (82691.9 1.43926316) (82692 3.02341747) (82692.5 0.0003)
        (82692.7 0.000051)))))
    |}];
  feed normalizer update1;
  [%expect
    {|
    (L2
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:21.330249000Z)
      (kind Delta) (bids ((82683.6 0) (82675.6 3.02386325))) (asks ())))
    |}];
  (* The new best-but-one bid pushes 82675.6 out of the top 10: the delta removes it. *)
  feed normalizer update2;
  [%expect
    {|
    (L2
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:21.331103000Z)
      (kind Delta) (bids ((82685 0.18141133) (82675.6 0))) (asks ())))
    |}]
;;

let%expect_test "updates before the snapshot are dropped" =
  let normalizer = Normalizer.create () in
  feed normalizer update1;
  [%expect {| |}];
  feed normalizer snapshot;
  feed normalizer update1;
  [%expect
    {|
    (L2
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:21.094243000Z)
      (kind Snapshot)
      (bids
       ((82689 0.00055351) (82688.7 0.000051) (82687.4 0.00090703)
        (82684.5 0.000051) (82683.8 0.00012081) (82683.7 0.22354849)
        (82683.6 3.02357136) (82681.5 3.02364775) (82680.4 0.000051)
        (82676.3 0.000051)))
      (asks
       ((82689.1 1.23752222) (82689.8 0.14580116) (82690 1.89824541)
        (82690.1 3.02333839) (82690.2 0.02418666) (82690.7 0.0055)
        (82691.9 1.43926316) (82692 3.02341747) (82692.5 0.0003)
        (82692.7 0.000051)))))
    (L2
     ((instrument kraken:BTC/USD) (exch_ts 2026-10-12T12:42:21.330249000Z)
      (kind Delta) (bids ((82683.6 0) (82675.6 3.02386325))) (asks ())))
    |}]
;;

let%expect_test "a missed update shows up as a checksum mismatch and a resubscribe" =
  let normalizer = Normalizer.create () in
  feed normalizer snapshot;
  ignore ([%expect.output] : string);
  (* [update1] is lost: [update2]'s checksum no longer matches. *)
  feed normalizer update2;
  [%expect {| (Resubscribe (BTC/USD)) |}];
  (* The book now waits for a new snapshot. *)
  feed normalizer update1;
  [%expect {| |}]
;;

let%expect_test "reset clears books after a reconnect" =
  let normalizer = Normalizer.create () in
  feed normalizer snapshot;
  Normalizer.reset normalizer;
  ignore ([%expect.output] : string);
  feed normalizer update1;
  [%expect {| |}]
;;
