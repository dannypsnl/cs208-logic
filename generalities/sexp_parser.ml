open Result_ext

type sexp = Sexplib.Type.t = Atom of string | List of sexp list

type error = (string, sexp) Annotated.t

type 'a parser = sexp -> ('a, error) result

type 'a seq_parser =
  sexp -> sexp list -> ('a * sexp list, error) result

let atom = function
  | Atom str -> Ok str
  | sexp     -> annotate_error sexp @@ Error "Expecting a single atom"

let close p parent items =
  let* result, _others = p parent items in
  Ok result

let match_tag k = function
  | List (Atom tag::entry_items) as sexp ->
     close (k tag) sexp entry_items
  | sexp ->
     annotate_error sexp @@ Error "Expecting a tagged entry"

let tagged tag k = function
  | List (Atom entry_tag::entry_items) as sexp when String.equal entry_tag tag ->
     close k sexp entry_items
  | sexp ->
     annotate_error sexp @@ Error (Printf.sprintf "Expecting (%s ...)" tag)

let fail msg parent _items =
  annotate_error parent @@ Error msg

let singleton p parent = function
  | [sexp] -> let* result = p sexp in Ok (result, [])
  | _      -> annotate_error parent @@ Error "Expecting a single entry"

let list p _parent items =
  let* results = Result_ext.traverse p items in
  Ok (results, [])

let extract_tagged_items tag =
  List.partition_map
    (function
     | List (Atom entry_tag::entry_items) as sexp when String.equal entry_tag tag ->
        Left (sexp, entry_items)
     | sexp ->
        Right sexp)

let consume_all tag k _parent items =
  let tagged, other = extract_tagged_items tag items in
  let* results = traverse (fun (parent, items) -> close k parent items) tagged in
  Ok (results, other)

let consume_one tag k parent items =
  match extract_tagged_items tag items with
  | [(parent, items)], others ->
     let* result = close k parent items in
     Ok (result, others)
  | [], _others ->
     annotate_error parent @@ Error (Printf.sprintf "Missing '%s' entry" tag)
  | _::_::_, _others ->
     annotate_error parent @@ Error (Printf.sprintf "Multiple '%s' entries" tag)

let consume_opt tag k parent items =
  match extract_tagged_items tag items with
  | [(parent, items)], others ->
     let* result = close k parent items in
     Ok (Some result, others)
  | [], others ->
     Ok (None, others)
  | _::_::_, _others ->
     annotate_error parent @@
       Error (Printf.sprintf "Multiple '%s' entries" tag)

let assert_nothing_left parent = function
  | [] -> Ok ((), [])
  | _others -> annotate_error parent @@ Error "Additional unexpected entries"

let ( let* ) c k parent items =
  match c parent items with
  | Ok (a, items) -> k a parent items
  | Error _ as r  -> r

let return x _parent items =
  Ok (x, items)

let lift e parent items =
  match e with
  | Ok a -> Ok (a, items)
  | Error e -> Error Annotated.{ detail = e; annotation = parent }
