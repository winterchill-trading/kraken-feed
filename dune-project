(lang dune 3.17)

(name kraken-feed)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/kraken-feed))

(package
 (name kraken-feed)
 (synopsis "Read-only public market data feed for Kraken spot and futures")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  async_ssl
  venue-net
  market-data
  fixed-decimal
  exchange-core
  ppx_jane
  yojson
  uri))
