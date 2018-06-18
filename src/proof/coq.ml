
let section = Section.make "coq"

let formula a = a.Dispatcher.SolverTypes.lit

(* Printing wrappers *)
(* ************************************************************************ *)

module Print = struct

  let pos = Tag.create ()
  let name = Tag.create ()
  let assoc = Tag.create ()
  type any = Any : Term.id * 'a Expr.tag * 'a -> any

  let () =
    List.iter (function Any (id, tag, v) -> Expr.Id.tag id tag v) [
      Any (Term.equal_id, name, "=");
      Any (Term.equal_id, pos, Pretty.Infix);
      Any (Term._Prop_id, name, "Prop");
      Any (Term.true_id,  name, "True");
      Any (Term.false_id, name, "False");
      Any (Term.not_id,   name, "~");
      Any (Term.not_id,   pos, Pretty.Prefix);
      Any (Term.imply_id, name, "->");
      Any (Term.imply_id, pos, Pretty.Infix);
      Any (Term.equiv_id, name, "<->");
      Any (Term.equiv_id, pos, Pretty.Infix);
      Any (Term.or_id,    name, {|\/|});
      Any (Term.or_id,    pos, Pretty.Infix);
      Any (Term.or_id,    assoc, Pretty.Right);
      Any (Term.and_id,   name, {|/\|});
      Any (Term.and_id,   pos, Pretty.Infix);
      Any (Term.and_id,   assoc, Pretty.Right);
    ]

  let t =
    let name = Escape.tagged_name ~tags:[name] in
    let rename = Escape.rename ~sep:'_' in
    let escape = Escape.umap (fun i -> function
        | None -> [ Uchar.of_char '_' ]
        | Some c ->
          let g = Uucp.Gc.general_category c in
          begin match g with
            | `Lu | `Ll | `Lt | `Lm | `Lo | `Sm -> [ c ]
            | `Nd when i > 1 -> [ c ]
            | _ -> [ Uchar.of_char '_' ]
          end) in
    Escape.mk ~lang:"coq" ~name ~escape ~rename

  let id fmt v = Escape.id t fmt v

  let get_status = function
    | { Term.term = Term.Id f } ->
      Expr.Id.get_tag f pos
    | _ -> None

  let binder_name = function
    | Term.Forall -> "forall"
    | Term.Exists -> "exists"
    | Term.Lambda -> "fun"

  let binder_sep = function
    | Term.Lambda -> " =>"
    | Term.Forall
    | Term.Exists -> ","

  let rec elim_implicits t args =
    match t.Term.term with
    | Term.Binder (Term.Forall, v, body) when Term.is_coq_implicit v ->
      elim_implicits body (List.tl args)
    | _ -> args

  let rec term fmt t =
    match t.Term.term with
    | Term.Type -> Format.fprintf fmt "Type"
    | Term.Id v -> id fmt v
    | Term.App _ ->
      let f, args = Term.uncurry ~assoc t in
      let args = elim_implicits f.Term.ty args in
      begin match get_status f, args with
        | None, [] ->
          Format.fprintf fmt "@[<hov>%a@]" term f
        | None, _ ->
          Format.fprintf fmt "@[<hov>(%a %a)@]" term f
            CCFormat.(list ~sep:(return "@ ") term) args
        | Some Pretty.Prefix, _ ->
          Format.fprintf fmt "@[<hov>%a %a@]" term f
            CCFormat.(list ~sep:(return "@ ") term) args
        | Some Pretty.Infix, _ ->
          let sep fmt () = Format.fprintf fmt "@ %a " term f in
          Format.fprintf fmt "@[<hov>(%a)@]" CCFormat.(list ~sep term) args
      end
    | Term.Let (v, e, body) ->
      Format.fprintf fmt "@[<v>@[<hv>let %a := @[<hov>%a@]@ in@]@ %a@]"
        id v term e term body
    | Term.Binder _ ->
      let kind, vars, body = Term.flatten_binder t in
      begin match kind with
        | `Arrow ->
          let tys = List.map (fun id -> id.Expr.id_type) vars in
          Format.fprintf fmt "(@[<hov>%a ->@ %a@])"
            CCFormat.(list ~sep:(return "@ -> ") term) tys term body
        | `Binder b ->
          let l = Term.concat_vars vars in
          Format.fprintf fmt "(@[<hov 2>%s @[<hov>%a@]%s@ %a@])"
            (binder_name b) var_lists l
            (binder_sep b) term body
      end

  and var_list fmt (ty, l) =
    assert (l <> []);
    Format.fprintf fmt "(%a:@ %a)"
      CCFormat.(list ~sep:(return "@ ") id) l term ty

  and var_lists fmt l =
    CCFormat.(list ~sep:(return "@ ") var_list) fmt l

end

(* Printing contexts *)
(* ************************************************************************ *)

let init fmt opt =
  Format.fprintf fmt
    "@\n(**@[<v>@ %s@ Input file: %s@]@ **)@]@\n@."
    "Proof automatically generated by Archsat"
    Options.(input_to_string opt.input.file)

let declare_loc fmt = function
  | None ->
    Format.fprintf fmt "(* Implicitly declared *)"
  | Some l ->
    Format.fprintf fmt "(* @[<hov>%a@] *)" Dolmen.ParseLocation.fmt l

let declare_id ?loc fmt id =
  Format.fprintf fmt "%a@\nParameter %a : %a.@\n@."
    declare_loc loc Print.id id Print.term id.Expr.id_type

let declare_hyp ?loc fmt id =
  Format.fprintf fmt "%a@\nAxiom %a : %a.@\n@."
    declare_loc loc Print.id id Print.term id.Expr.id_type

let declare_goal ?loc fmt id =
  Format.fprintf fmt "%a@\nTheorem %a : %a.@."
    declare_loc loc Print.id id Print.term id.Expr.id_type

let declare_goal_term ?loc fmt id =
  Format.fprintf fmt "%a@\n@[<hv 2>Definition %a :@ %a :=@ "
    declare_loc loc Print.id id Print.term id.Expr.id_type

let proof_context pp fmt x =
  Format.fprintf fmt "@[<hov 2>Proof.@\n%a@]@\nQed.@." pp x

let proof_term_context pp fmt x =
  Format.fprintf fmt "%a@]@\n." pp x

(*
(* Coq tactic helpers *)
(* ************************************************************************ *)

let exact fmt format =
  Format.fprintf fmt ("exact (" ^^ format ^^ ").")

let pose_proof ctx f fmt format =
  Format.kfprintf (fun fmt ->
      Format.fprintf fmt ") as %a." (Proof.Ctx.intro ctx) f)
    fmt ("pose proof (" ^^ format)


let fun_binder fmt args =
  CCFormat.(list ~sep:(return "@ ") Print.id) fmt args

let app_t ctx fmt (f, l) =
  Format.fprintf fmt "%a @[<hov>%a@]"
    (Proof.Ctx.named ctx) f CCFormat.(list ~sep:(return "@ ") Print.term) l

let sequence ctx pp start fmt l =
  let rec aux ctx pp fmt curr = function
    | [] -> curr
    | x :: r ->
      let next = Proof.Ctx.new_name ctx in
      Format.fprintf fmt "pose proof (%a) as %s.@ " (pp curr) x next;
      aux ctx pp fmt next r
  in
  aux ctx pp fmt start l

(* Printing tactic coq proofs *)
(* ************************************************************************ *)

(* Getting tactics from plugins *)
let _tactic_cache =
  CCCache.unbounded 4013
    ~eq:(fun l l' -> Dispatcher.(l.id = l'.id))
    ~hash:(fun l -> CCHash.int l.Dispatcher.id)

let _default_tactic = tactic (fun fmt _ ->
    Format.fprintf fmt "(* TODO: complete proof *)"
  )

let get_tactic =
  CCCache.with_cache _tactic_cache (fun lemma ->
      Util.debug ~section "Getting tactic for %s/%s"
        lemma.Dispatcher.plugin_name lemma.Dispatcher.proof_name;
      match Dispatcher.ask lemma.Dispatcher.plugin_name
              (Tactic (lemma.Dispatcher.proof_info)) with
      | Some p -> p
      | None ->
        Util.warn ~section "Got no coq proof from plugin %s for proof %s"
          lemma.Dispatcher.plugin_name lemma.Dispatcher.proof_name;
        _default_tactic
    )

module Tactic = Msat.Coq.Make(Solver.Proof)(struct

    (** Print mSAT atoms *)
    let print_atom = Print.atom

    (** Prove assumptions.
        These raise en Error, because assumptions should only
        be used temporarily (to help with proof search).
        TODO:use a proper exception instead of assert false *)
    let prove_assumption fmt name clause = assert false

    let assert_clause fmt (dest, a) =
      let pp_atom fmt atom =
        let pos = Dispatcher.SolverTypes.(atom.var.pa) in
        if atom == pos then
          Format.fprintf fmt "~ %a" Print.atom atom
        else
          Format.fprintf fmt "~ ~ %a" Print.atom pos
      in
      Format.fprintf fmt "assert (%s: @[<hv>%a ->@ False@])."
        dest CCFormat.(array ~sep:(return " ->@ ") pp_atom) a

    let intro_clause ctx fmt a =
      let aux fmt atom = Proof.Ctx.intro ctx fmt (Expr.Formula.neg @@ formula atom) in
      Format.fprintf fmt "intros %a." CCFormat.(array ~sep:(return " ") aux) a

    let destroy_disj ctx fmt (orig, a, l) =
      match l with
      | [] -> assert false
      | [p] ->
        let () = Proof.Ctx.add_force ctx p orig in
        let f = formula a.(0) in
        Format.fprintf fmt "exact (%a %a)."
          (Proof.Ctx.named ctx) (Expr.Formula.neg f)
          (Proof.Ctx.named ctx) f
      | _ ->
        let order = Expr.L (List.map (fun f -> Expr.F f) l) in
        Format.fprintf fmt "@[<hov 2>destruct %s as %a.@ %a@]" orig
          (Print.pattern_or (Proof.Ctx.intro ctx)) order
          CCFormat.(list ~sep:(return "@ ") (fun fmt p ->
              let f = CCOpt.get_exn @@ CCArray.find (fun x ->
                  let f = formula x in
                  if Expr.Formula.equal f p then Some f else None
                ) a in
              if Expr.Formula.(equal f_false) f then
                Format.fprintf fmt "exact %a." (Proof.Ctx.named ctx) f
              else
                Format.fprintf fmt "exact (%a %a)."
                  (Proof.Ctx.named ctx) (Expr.Formula.neg f)
                  (Proof.Ctx.named ctx) f
            )) l

    (** clausify or-separated clauses into mSAT encoding of clauses *)
    let clausify fmt (orig, l, dest, a) =
      let ctx = Print.ctx "Ax" in
      Format.fprintf fmt "@[<v 2>%a@ @[<hv>%a@ %a@]@]"
        assert_clause (dest, a)
        (intro_clause ctx) a
        (destroy_disj ctx) (orig, a, l)
    (** destruct already proved hyp *)

    (** Prove hypotheses. All hypothses (including negated goals)
        should already be available under their official names
        (i.e. full name of Dolmen id associated with the clause),
        so it should really just be a matter of introducing the right
        name for it. *)
    let prove_hyp fmt name clause =
      match Solver.hyp_id clause with
      | None -> assert false (* All hyps should must have been given an id. *)
      | Some id ->
        Format.fprintf fmt "(* Introducing hypothesis %a as %s *)@\n%a@\n"
          Print.dolmen id name clausify
          ((Format.asprintf "%a" Print.dolmen id), (Proof.find_hyp id),
           name, clause.Dispatcher.SolverTypes.atoms)

    (** Negated formulas in a clause will be introduced as double
        negations, while context lookups will try and find
        the original formula (because double negation is automatically
        erased by the smart constructors in Expr), so this function
        will be used ot normalize the double negations. *)
    let not_not ctx fmt f =
      Format.fprintf fmt "apply %a; clear %a; intro %a."
        (Proof.Ctx.named ctx) f
        (Proof.Ctx.named ctx) f
        (Proof.Ctx.named ctx) f

    let normalize_pred = function
      | Pred p -> p
      | All -> (fun _ -> true)
      | Mem l -> (fun f -> List.exists (Expr.Formula.equal f) l)

    let normalize_clause selector ctx fmt a =
      let p = normalize_pred selector in
      Array.iter (fun atom ->
          let pos = Dispatcher.SolverTypes.(atom.var.pa) in
          if atom == pos then ()
          else if p (formula pos) then
            Format.fprintf fmt "%a@ "
              (not_not ctx) (formula pos)
        ) a

    (** Prove lemmas. *)
    let prove_lemma fmt name clause =
      let lemma = CCOpt.get_exn (extract clause) in
      let tactic = get_tactic lemma in
      Format.fprintf fmt "(* Proving lemma %s/%s as %s *)@\n"
        lemma.Dispatcher.plugin_name lemma.Dispatcher.proof_name name;
      (* Assert the lemma *)
      let ctx = Print.ctx tactic.prefix in
      let a = clause.Dispatcher.SolverTypes.atoms in
      Format.fprintf fmt "@[<v 2>%a@ @[<hv>%a@ %a%a@]@]@ "
        assert_clause (name, a)
        (intro_clause ctx) a
        (normalize_clause tactic.normalize ctx) a
        tactic.proof ctx

  end)

(* Printing proofs *)
(* ************************************************************************ *)

(** Introduce the goals as hypotheses, using diabolical classical logic !!
    Separated into two functions. Depends on the number of goals:
    - 0 goals : nothing to do, ^^
    - 1 goal  : NNPP, and intro
    - n goals : NNPP, and deMorgan to decompose the '~ (\/ a_i)'
                into hypotheses '~ a_i' *)
let rec intro_aux fmt i = function
  | [] | [_] -> assert false
  | [x, gx; y, gy] ->
    Format.fprintf fmt "destruct (%s _ _ G%d) as (%a, %a). clear G%d.@\n"
      "Coq.Logic.Classical_Prop.not_or_and" i Print.dolmen x Print.dolmen y i
  | (x, gx) :: r ->
    Format.fprintf fmt "destruct (%s _ _ G%d) as (%a, G%d). clear G%d.@\n"
      "Coq.Logic.Classical_Prop.not_or_and" i Print.dolmen x (i + 1) i;
    intro_aux fmt (i + 1) r

let pp_intros fmt l =
  match l with
  | [] -> () (* goal is already 'False', nothing to do *)
  (** When a single goal is *not* is negation, it means that it is
      originally a negation, so we can directly introduce it. *)
  | [ id, { Expr.formula = (Expr.Not _ | Expr.True )} ] ->
    Format.fprintf fmt "(* Introduce the goal(s) into the hyps *)@\n";
    Format.fprintf fmt "apply Coq.Logic.Classical_Prop.NNPP. ";
    Format.fprintf fmt "intro %a.@\n" Print.dolmen id
  (** Interesting case (faster than match every other variant) *)
  | [ id, _ ] ->
    Format.fprintf fmt "(* Introduce the goal(s) into the hyps *)@\n";
    Format.fprintf fmt "intro %a.@\n" Print.dolmen id
  (** General case *)
  | _ ->
    Format.fprintf fmt "(* Introduce the goal(s) into the hyps *)@\n";
    Format.fprintf fmt "apply Coq.Logic.Classical_Prop.NNPP. ";
    begin match l with
      | [] -> assert false
      | [id, g] ->
        Format.fprintf fmt "intro %a.@\n" Print.dolmen id
      | _ ->
        Format.fprintf fmt "intro G0.@\n";
        intro_aux fmt 0 l
    end

let pp_goals fmt = function
  | [] -> Format.fprintf fmt "False"
  | l -> CCFormat.(list ~sep:(return {|@ \/@ |}) Print.formula) fmt l

(** Print both the goals (as theorem), and its proof. *)
let print_proof fmt proof =
  Format.pp_set_margin fmt 100;
  let names, goals = List.split (Proof.get_goals ()) in
  let l = Solver.Proof.unsat_core proof in
  let goal = match goals with [] -> false | _ -> true in
  let preludes = Preludes.(from_tactics (empty ~goal) l) in
  Format.fprintf fmt "@\n(* Coq proof generated by Archsat *)@\n@\n";
  Format.fprintf fmt "@[<v>%a@]" Preludes.print preludes;
  Format.fprintf fmt "@\nTheorem goal : @[<hov>%a@].@\n" pp_goals goals;
  let l' = List.combine names (List.map Expr.Formula.neg goals) in
  Format.fprintf fmt
    "@[<hov 2>Proof.@\n%a@\n%a@]@\nQed.@."
    pp_intros l' Tactic.print proof

*)
