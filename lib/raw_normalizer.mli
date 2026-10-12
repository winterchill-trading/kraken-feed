(** {!Normalizer} as a {!Market_data.Normalizer.S}, so [rebuild-norm] can turn
    market-recorder raw files of Kraken back into events:
    [Market_data.Rebuild_norm.command [ (module Kraken_feed.Raw_normalizer) ]].

    Books are assumed to be subscribed at depth 10, the {!Live_feed} default; a
    [disconnect] clears them as a reconnect does. Resubscriptions after a checksum
    mismatch are not sent (there is no connection); the book stays empty until the
    snapshot the live feed asked for shows up in the recording. *)

include Market_data.Normalizer.S with type t = Normalizer.t
