open! Core

let table =
  lazy
    (Array.init 256 ~f:(fun n ->
       let c = ref n in
       for _ = 1 to 8 do
         c := if !c land 1 = 1 then 0xEDB88320 lxor (!c lsr 1) else !c lsr 1
       done;
       !c))
;;

let crc32 s =
  let table = Lazy.force table in
  let crc =
    String.fold s ~init:0xFFFFFFFF ~f:(fun crc ch ->
      table.(crc lxor Char.to_int ch land 0xFF) lxor (crc lsr 8))
  in
  crc lxor 0xFFFFFFFF
;;

let format_number number =
  String.filter (Wire.Number.to_string number) ~f:(fun c -> not (Char.equal c '.'))
  |> String.lstrip ~drop:(Char.equal '0')
;;

let of_levels ~bids ~asks =
  let buf = Buffer.create 512 in
  let add levels =
    List.iter (List.take levels 10) ~f:(fun ({ price; qty } : Wire.Level.t) ->
      Buffer.add_string buf (format_number price);
      Buffer.add_string buf (format_number qty))
  in
  add asks;
  add bids;
  crc32 (Buffer.contents buf)
;;
