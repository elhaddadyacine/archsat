(* This file is free software, part of Archsat. See file "LICENSE" for more details. *)

let section = Section.make ~parent:Dispatcher.section "eq"

(* Module initialisation *)
(* ************************************************************************ *)

module D = Dispatcher
module E = Closure.Eq(Expr.Term)

module S = Set.Make(Expr.Term)
module M = Map.Make(Expr.Id.Const)

type info =
  | Trivial of Expr.term
  | Chain of Expr.term list

type D.lemma_info += Eq of info

(* Union-find payloads and callbacks *)
(* ************************************************************************ *)

type load = {
  vars : Expr.term list;
  elts : Expr.term list M.t;
}

let print fmt t =
  Format.fprintf fmt "< %a >" Expr.Term.print (E.repr t)

let gen = function
  | { Expr.term = Expr.Var _ } ->
    assert false
  | { Expr.term = Expr.Meta _ } as t ->
    { vars = [t]; elts = M.empty; }
  | { Expr.term = Expr.App (f, _, _) } as t ->
    { vars = []; elts = M.singleton f [t]; }

let merge a b =
  let vars = a.vars @ b.vars in
  let aux _ x y = match x, y with
    | None, None -> None
    | Some l, Some l' -> Some (l @ l')
    | Some l, None | None, Some l -> Some l
  in
  { vars; elts = M.merge aux a.elts b.elts; }

let callback, register_callback =
  let l = ref [] in
  let callback a b c =
    Util.debug ~section "Merging %a / %a ==> %a"
      print a print b print c;
    List.iter (fun (name, f) ->
        if Dispatcher.Plugin.(is_active (find name)) then
          f a b c) !l
  in
  let register name f =
    l := (name, f) :: !l
  in
  callback, register

let st = E.create
    ~section:(Section.make ~parent:section "union-find")
    ~gen ~merge ~callback D.stack

(* Accessors to the equality closure *)
(* ************************************************************************ *)

module Class = struct

  type t = load E.eq_class

  let find x = E.get_class st x

  let repr t = E.repr t

  let ty t = Expr.((E.repr t).t_type)

  let hash c = Expr.Term.hash (repr c)
  let equal c c' = Expr.Term.equal (repr c) (repr c')
  let compare c c' = Expr.Term.compare (repr c) (repr c')

  let print = print

  let mem t x =
    Expr.Term.equal (repr t) (repr (find x))

  let fold f x t =
    let l = E.load t in
    let aux _ l acc = List.fold_left f acc l in
    M.fold aux l.elts (List.fold_left f x l.vars)

  let find_top t f =
    let load = E.load t in
    try M.find f load.elts
    with Not_found -> []

end

(* Link equalities and non-ordered tuples *)
(* ************************************************************************ *)

module H = Backtrack.Hashtbl(struct
    type t = Expr.term * Expr.term
    let equal = CCPair.equal Expr.Term.equal Expr.Term.equal
    let hash (a, b) = CCHash.combine2 (Expr.Term.hash a) (Expr.Term.hash b)
  end)

let eq_table = H.create Dispatcher.stack
let neq_table = H.create Dispatcher.stack

let fetch_eq a b =
  let x, y = if Expr.Term.compare a b < 0 then a, b else b, a in
  try H.find eq_table (x, y)
  with Not_found -> Expr.Formula.eq a b

let add_eq_table f a b =
  let x, y = if Expr.Term.compare a b < 0 then a, b else b, a in
  H.add eq_table (x, y) f

let fetch_neq a b =
  let x, y = if Expr.Term.compare a b < 0 then a, b else b, a in
  try H.find neq_table (x, y)
  with Not_found -> Expr.Formula.neg @@ Expr.Formula.eq a b

let add_neq_table f a b =
  let x, y = if Expr.Term.compare a b < 0 then a, b else b, a in
  H.add neq_table (x, y) f


(* McSat Plugin for equality *)
(* ************************************************************************ *)

let name = "eq"

let watch_t = D.mk_watch (module Expr.Term) name
let watch_f = D.mk_watch (module Expr.Formula) name

let eval_pred = function
  | { Expr.formula = Expr.Equal (a, b) } as f ->
    begin try
        let a' = D.get_assign a in
        let b' = D.get_assign b in
        Util.debug ~section "Eval [%a] %a == %a"
            Expr.Print.formula f Expr.Print.term a' Expr.Print.term b';
        Some (Expr.Term.equal a' b', [a; b])
      with D.Not_assigned _ ->
        None
    end
  | { Expr.formula = Expr.Not { Expr.formula = Expr.Equal (a, b) } } as f ->
    begin try
        let a' = D.get_assign a in
        let b' = D.get_assign b in
        Util.debug ~section "Eval [%a] %a <> %a"
            Expr.Print.formula f Expr.Print.term a' Expr.Print.term b';
        Some (not (Expr.Term.equal a' b'), [a; b])
      with D.Not_assigned _ ->
        None
    end
  | _ -> None

let f_eval f () =
  match eval_pred f with
  | Some(true, lvl) -> D.propagate f lvl
  | Some(false, lvl) -> D.propagate (Expr.Formula.neg f) lvl
  | None -> ()

let mk_expl (a, b, l) =
  let rec aux acc = function
    | [] | [_] -> acc
    | x :: ((y :: _) as r) ->
      aux (fetch_eq x y :: acc) r
  in
  (Expr.Formula.neg (fetch_neq a b)) :: (List.rev_map Expr.Formula.neg (aux [] l))

let mk_proof l =
  match l with
  | [] -> assert false
  | [x] ->
    Dispatcher.mk_proof name "trivial" (Eq (Trivial x))
  | _ ->
    Dispatcher.mk_proof name "eq-trans" (Eq (Chain l))

let wrap f x y =
  try
    f st x y
  with E.Unsat (a, b, l) ->
    Util.debug ~section "Conflict found while adding hypothesis : %a ~ %a@ @[<hov>{%a}@]"
      Expr.Print.term x Expr.Print.term y
      CCFormat.(list ~sep:(return ",@ ") Expr.Print.term) l;
    raise (D.Absurd (mk_expl (a, b, l), mk_proof l))

let tag x = fun () ->
  try
    Util.debug ~section "Tagging %a -> %a"
      Expr.Print.term x Expr.Print.term (D.get_assign x);
    E.add_tag st x (D.get_assign x)
  with E.Unsat (a, b, l) ->
    Util.debug ~section "Conflict found while tagging : %a -> %a@ @[<hov>{%a}@]"
      Expr.Print.term x Expr.Print.term (D.get_assign x)
      CCFormat.(list ~sep:(return ",@ ") Expr.Print.term) l;
    let res = mk_expl (a, b, l) in
    let proof = mk_proof l in
    raise (D.Absurd (res, proof))

let eq_assign x =
  try
    Util.debug ~section "Looking up tag for: %a" Expr.Print.term x;
    begin match E.find_tag st x with
      | _, Some (_, v) ->
        Util.debug ~section "  Found tag : %a" Expr.Print.term v;
        v
      | y, None ->
        Util.debug ~section "  No tag found, Looking up repr : %a" Expr.Print.term y;
        let res = try D.get_assign y with D.Not_assigned _ -> y in
        res
    end
  with E.Unsat (a, b, l) ->
    Util.error ~section "Wut ?!";
    raise (D.Absurd (mk_expl (a, b, l), mk_proof l))

let assume = function
  | { Expr.formula = Expr.Equal (a, b)} as f ->
    Util.debug ~section "Assume: %a == %a" Expr.Term.print a Expr.Term.print b;
    add_eq_table f a b;
    wrap E.add_eq a b
  | { Expr.formula = Expr.Not { Expr.formula = Expr.Equal (a, b)} } as f ->
    Util.debug ~section "Assume: %a <> %a" Expr.Term.print a Expr.Term.print b;
    add_neq_table f a b;
    wrap E.add_neq a b
  | _ -> ()

let set_handler_aux v =
  if not Expr.(Ty.equal v.id_type Ty.prop) then
    Expr.Id.set_valuation v 0 (Expr.Assign eq_assign)

let rec set_handler_term = function
  | { Expr.term = Expr.Var v } -> assert false
  | { Expr.term = Expr.Meta m } -> set_handler_aux Expr.(m.meta_id)
  | { Expr.term = Expr.App (f, _, l) } ->
    if not Expr.(Ty.equal f.id_type.fun_ret Ty.prop) then begin
      Expr.Id.set_valuation f 0 (Expr.Assign eq_assign)
    end;
    List.iter set_handler_term l

let rec set_handler = function
  | { Expr.formula = Expr.Equal (a, b) } when Expr.Term.equal a b ->
    set_handler_term a
  | { Expr.formula = Expr.Equal (a, b) } ->
    set_handler_term a;
    set_handler_term b
  | { Expr.formula = Expr.Pred p } ->
    set_handler_term p
  | { Expr.formula = Expr.Not f } ->
    set_handler f
  | _ -> ()

let rec set_watcher_term t =
  if not Expr.(Ty.equal t.t_type Ty.prop) then
    watch_t t 1 [t] (tag t);
  match t with
  | { Expr.term = Expr.Var v } -> assert false
  | { Expr.term = Expr.Meta m } -> ()
  | { Expr.term = Expr.App (f, _, l) } -> List.iter set_watcher_term l

let rec set_watcher = function
  | { Expr.formula = Expr.Equal (a, b) } as f when Expr.Term.equal a b ->
    D.push [f] (D.mk_proof name "trivial" (Eq (Trivial a)));
    set_watcher_term a
  | { Expr.formula = Expr.Equal (a, b) } as f ->
    watch_f f 1 [a; b] (f_eval f);
    set_watcher_term a;
    set_watcher_term b
  | { Expr.formula = Expr.Pred p } ->
    set_watcher_term p
  | { Expr.formula = Expr.Not f } ->
    set_watcher f
  | _ -> ()

(* Proof managament *)
(* ************************************************************************ *)

let dot_info = function
  | Trivial _ -> None, []
  | Chain l -> None, List.map (CCFormat.const Dot.Print.term) l

let to_pairs l =
  let rec aux first acc = function
    | [] -> assert false
    | [last] ->
      (first, last), List.rev acc
    | x :: ((y :: _) as r) ->
      aux first ((x, y) :: acc) r
  in
  match List.map Term.of_term l with
  | [] | [_] -> assert false
  | (first :: _) as l' -> aux first [] l'

let coq_proof = function
  | Trivial _x -> (* We want to prove ~ ~ [x = x] -> False *)
    (fun pos -> pos
                |> Logic.not_not_intro ~prefix:"E"
                |> Eq.refl)
  | Chain l -> (* We want to prove:
                  ~ ~ x1 = x2 -> ~ ~ x2 = x3 -> ... -> ~ ~ x3 = x_n -> ~ x1 = x_n -> False
                  with l = [x1; x2; ...: x_n]. *)
    let (x, y), l' = to_pairs l in
    let f = Term.apply Term.equal_term [Term.ty x; x; y] in
    (** We use a ref to store the equalities introduced, because they might
        be swapped (i.e we expect [~ ~ a = b] and instead introduce [~ ~ b = a],
        which is actually not a problem, since we immediately eliminate this double
        negation, but we can't generically generate the list of formulas to normalize,
        because of potential swaps. Also, the coercions can't help us (no theorem to
        coerce double negated equalities). *)
    let r = ref [] in
    (fun pos -> pos
                |> Logic.introN "E" (List.length l' + 1)
                    ~post:(fun f pos -> r := f :: !r; pos)
                |> Logic.fold (Logic.normalize "E") !r
                |> Logic.find (Term.app Term.not_term f) @@ Logic.apply1 []
                |> Eq.trans l')

(* Handler & Plugin registering *)
(* ************************************************************************ *)

let handle : type ret. ret D.msg -> ret option = function
  | Dot.Info Eq info -> Some (dot_info info)
  | Proof.Lemma Eq info -> Some (coq_proof info)
  | _ -> None

let register () =
  D.Plugin.register name
    ~descr:"Ensures consistency of assignment with regards to the equality predicates."
    (D.mk_ext ~handle:{D.handle} ~section ~assume ~set_handler ~set_watcher ~eval_pred ())

