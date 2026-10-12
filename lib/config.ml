open! Core

type t =
  { spot_url : Uri.t
  ; futures_url : Uri.t
  }

let sexp_of_t { spot_url; futures_url } =
  [%sexp
    { spot_url = (Uri.to_string spot_url : string)
    ; futures_url = (Uri.to_string futures_url : string)
    }]
;;

let mainnet =
  { spot_url = Uri.of_string "wss://ws.kraken.com/v2"
  ; futures_url = Uri.of_string "wss://futures.kraken.com/ws/v1"
  }
;;

let create ?(spot_url = mainnet.spot_url) ?(futures_url = mainnet.futures_url) () =
  { spot_url; futures_url }
;;
