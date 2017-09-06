
module D = Dispatcher

let section = Section.make "dot"

(* Printing expressions in HTML *)
(* ************************************************************************ *)

module Print = struct

  let t =
    let name = function
      | Escape.Any.Dolmen id -> Dolmen.Id.full_name id
      | Escape.Any.Id id ->
        begin match Expr.Id.get_tag id Expr.Print.pretty with
          | None -> id.Expr.id_name
          | Some Expr.Print.(Infix s | Prefix s) -> s
        end
    in
    let rename = Escape.rename ~sep:'_' in
    let escape = Escape.umap (fun i -> function
        | None -> [ Uchar.of_char '_' ]
        | Some c ->
          if Uchar.equal c (Uchar.of_char '>') then
            [ Uchar.of_char '&';
              Uchar.of_char 'g';
              Uchar.of_char 't';
              Uchar.of_char ';' ]
          else if Uchar.equal c (Uchar.of_char '<') then
            [ Uchar.of_char '&';
              Uchar.of_char 'l';
              Uchar.of_char 't';
              Uchar.of_char ';' ]
          else if Uchar.equal c (Uchar.of_char '&') then
            [ Uchar.of_char '&';
              Uchar.of_char 'a';
              Uchar.of_char 'm';
              Uchar.of_char 'p';
              Uchar.of_char ';' ]
          else if Uchar.equal c (Uchar.of_char '"') then
            [ Uchar.of_char '&';
              Uchar.of_char 'q';
              Uchar.of_char 'u';
              Uchar.of_char 'o';
              Uchar.of_char 't';
              Uchar.of_char ';' ]
          else
            [ c ]
      ) in
    Escape.mk ~lang:"html" ~name ~escape ~rename

  let dolmen fmt id = Escape.dolmen t fmt id

  open Expr

  let id fmt v =
    Escape.id t fmt v

  let meta fmt m =
    Format.fprintf fmt "m%d_%a"
      ((m.meta_index) : _ meta_index :> int) id m.meta_id

  let ttype fmt = function Type -> Format.fprintf fmt "Type"

  let rec ty fmt t = match t.ty with
    | TyVar v -> id fmt v
    | TyMeta m -> meta fmt m
    | TyApp (f, []) -> id fmt f
    | TyApp (f, l) ->
      begin match Tag.get f.id_tags Print.pretty with
        | None ->
          Format.fprintf fmt "@[<hov 2>%a(%a)@]"
            id f CCFormat.(list ~sep:(return ",") ty) l
        | Some Print.Prefix _ ->
          assert (List.length l = 1);
          Format.fprintf fmt "@[<hov 2>%a %a@]"
            id f CCFormat.(list ~sep:(return "") ty) l
        | Some Print.Infix _ ->
          let sep fmt () = Format.fprintf fmt " %a@ " id f in
          Format.fprintf fmt "@[<hov 2>(%a)@]" (CCFormat.list ~sep ty) l
      end

  let params fmt = function
    | [] -> ()
    | l -> Format.fprintf fmt "∀ @[<hov>%a@].@ "
             CCFormat.(list ~sep:(return ",@ ") id) l

  let signature print fmt f =
    match f.fun_args with
    | [] -> Format.fprintf fmt "@[<hov 2>%a%a@]" params f.fun_vars print f.fun_ret
    | l -> Format.fprintf fmt "@[<hov 2>%a%a ->@ %a@]" params f.fun_vars
             CCFormat.(list ~sep:(return " ->@ ") print) l print f.fun_ret

  let fun_ty = signature ty
  let fun_ttype = signature ttype

  let id_pretty fmt v =
    match Tag.get v.id_tags Print.pretty with
    | None -> ()
    | Some Print.Prefix _ -> Format.fprintf fmt "[%a]" id v
    | Some Print.Infix _ -> Format.fprintf fmt "(%a)" id v

  let id_type print fmt v =
    Format.fprintf fmt "@[<hov 2>%a%a :@ %a@]" id v id_pretty v print v.id_type

  let id_ty = id_type ty
  let id_ttype = id_type ttype

  let rec term fmt t = match t.term with
    | Var v -> id fmt v
    | Meta m -> meta fmt m
    | App (f, [], []) -> id fmt f
    | App (f, tys, args) ->
      begin match Tag.get f.id_tags Print.pretty with
        | None ->
          begin match tys with
            | [] ->
              Format.fprintf fmt "%a(@[<hov>%a@])"
                id f CCFormat.(list ~sep:(return ",@ ") term) args
            | _ ->
              Format.fprintf fmt "%a(@[<hov>%a%a%a@])" id f
                CCFormat.(list ~sep:(return ",@ ") ty) tys
                (CCFormat.return ";@ ") ()
                CCFormat.(list ~sep:(return ",@ ") term) args
          end
        | Some Print.Prefix _ ->
          Format.fprintf fmt "@[<hov>%a(%a)@]"
            id f CCFormat.(list ~sep:(return ",@ ") term) args
        | Some Print.Infix _ ->
          let sep fmt () = Format.fprintf fmt " %a@ " id f in
          Format.fprintf fmt "(%a)" CCFormat.(list ~sep term) args
      end

  let rec formula_aux fmt f =
    let aux fmt f = match f.formula with
      | Equal _ | Pred _ | True | False -> formula_aux fmt f
      | _ -> Format.fprintf fmt "(@ %a@ )" formula_aux f
    in
    match f.formula with
    | Pred t -> Format.fprintf fmt "%a" term t
    | Equal (a, b) -> Format.fprintf fmt "@[<hov>%a@ =@ %a@]" term a term b

    | True  -> Format.fprintf fmt "⊤"
    | False -> Format.fprintf fmt "⊥"
    | Not f -> Format.fprintf fmt "@[<hov 2>¬ %a@]" aux f
    | And l -> Format.fprintf fmt "@[<hov>%a@]"
                 CCFormat.(list ~sep:(return " ∧@ ") aux) l
    | Or l  -> Format.fprintf fmt "@[<hov>%a@]"
                 CCFormat.(list ~sep:(return " ∨@ ") aux) l

    | Imply (p, q)    -> Format.fprintf fmt "@[<hov>%a@ ⇒@ %a@]" aux p aux q
    | Equiv (p, q)    -> Format.fprintf fmt "@[<hov>%a@ ⇔@ %a@]" aux p aux q

    | All (l, _, f)   -> Format.fprintf fmt "@[<hov 2>∀ @[<hov>%a@].@ %a@]"
                           CCFormat.(list ~sep:(return ",@ ") id_ty) l formula_aux f
    | AllTy (l, _, f) -> Format.fprintf fmt "@[<hov 2>∀ @[<hov>%a@].@ %a@]"
                           CCFormat.(list ~sep:(return ",@ ") id_ttype) l formula_aux f
    | Ex (l, _, f)    -> Format.fprintf fmt "@[<hov 2>∃ @[<hov>%a@].@ %a@]"
                           CCFormat.(list ~sep:(return ",@ ") id_ty) l formula_aux f
    | ExTy (l, _, f)  -> Format.fprintf fmt "@[<hov 2>∃ @[<hov>%a@].@ %a@]"
                           CCFormat.(list ~sep:(return ",@ ") id_ttype) l formula_aux f

  let formula fmt f = Format.fprintf fmt "⟦@[<hov>%a@]⟧" formula_aux f

  let mapping fmt m =
    Mapping.fold m ()
      ~ty_var:(fun v t () -> Format.fprintf fmt "%a ↦ %a;@ " id v ty t)
      ~ty_meta:(fun m t () -> Format.fprintf fmt "%a ↦ %a;@ " meta m ty t)
      ~term_var:(fun v t () -> Format.fprintf fmt "%a ↦ %a;@ " id v term t)
      ~term_meta:(fun m t () -> Format.fprintf fmt "%a ↦ %a;@ " meta m term t)

end

(* Printing wrappers *)
(* ************************************************************************ *)

let buffer = Buffer.create 1013

let sfmt =
  let fmt = Format.formatter_of_buffer buffer in
  let f = Format.pp_get_formatter_out_functions fmt () in
  let () = Format.pp_set_formatter_out_functions fmt
      Format.{ f with out_newline = function () ->
          f.out_string {|<br align="left" />|} 0 19}
  in
  fmt

let box pp x fmt () =
  let () = Buffer.clear buffer in
  let () = Format.fprintf sfmt "%a@?" pp x in
  let s = Buffer.contents buffer in
  Format.fprintf fmt "%s" s

let boxed pp = box pp ()

(* Printing functor argument *)
(* ************************************************************************ *)

type _ D.msg +=
  | Info : D.lemma_info ->
    (string option * ((Format.formatter -> unit -> unit) list)) D.msg

module Arg = struct

  let print_atom fmt a =
    let f = a.Dispatcher.SolverTypes.lit in
    box Print.formula f fmt ()

  let hyp_info c =
    let id = CCOpt.get_exn @@ Solver.hyp_id c in
    "Hypothesis", Some "YELLOW",
    [fun fmt () -> Print.dolmen fmt id]

  let lemma_info c =
    let lemma =
      match c.Dispatcher.SolverTypes.cpremise with
      | Dispatcher.SolverTypes.Lemma l -> l
      | _ -> assert false
    in
    let name = Format.sprintf "%s/%s" lemma.D.plugin_name lemma.D.proof_name in
    let color, fmts =
      match D.ask lemma.D.plugin_name (Info lemma.D.proof_info) with
      | Some r -> r
      | None ->
        Util.warn ~section "Got no lemma info from plugin %s for proof %s"
          lemma.D.plugin_name lemma.D.proof_name;
        Some "WHITE", [fun fmt () -> Format.fprintf fmt "N/A"]
    in
    name, color, List.map boxed fmts

  let assumption_info c =
    "assumption", Some "YELLOW", []

end

(* Printing proofs *)
(* ************************************************************************ *)

module P = Msat.Dot.Make(Solver.Proof)(Arg)

let print = P.print
