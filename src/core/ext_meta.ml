
module H = Hashtbl.Make(Expr.Formula)

exception Found_unif

(* Logging sections *)
(* ************************************************************************ *)

let section = Util.Section.make ~parent:Dispatcher.section "meta"
let log i fmt = Util.debug ~section i fmt

let sup_section = Util.Section.make ~parent:section "sup"
let unif_section = Util.Section.make ~parent:section "unif"
let rigid_section = Util.Section.make ~parent:section "rigid"

(* Create the necessary sections for superposition *)
let () = ignore (Superposition.empty (fun _ -> assert false) sup_section)

(* Extension parameters *)
(* ************************************************************************ *)

(* To see the actual default values, see the cmd line options *)
let meta_start = ref 0
let meta_incr = ref false
let meta_delay = ref (0, 0)
let meta_max = ref 10

let sup_max_coef = ref 1
let sup_max_const = ref 0

let rigid_max_depth = ref 1
let rigid_round_incr = ref 2

(* New meta delay *)
let delay i =
  let a, b = !meta_delay in
  a * i * i + b

(* Heuristics *)
type heuristic =
  | No_heuristic
  | Goal_directed

let heuristic_setting = ref No_heuristic

let heur_list = [
  "none", No_heuristic;
  "goal", Goal_directed;
]

let heur_conv = Cmdliner.Arg.enum heur_list

let score u = match !heuristic_setting with
  | No_heuristic -> 0
  | Goal_directed -> Heuristic.goal_directed u

(* Unification options *)
type unif =
  | No_unif
  | Simple
  | ERigid
  | SuperAll
  | SuperEach
  | Auto

let unif_setting = ref No_unif

let unif_list = [
  "none", No_unif;
  "simple", Simple;
  "rigid", ERigid;
  "super", SuperAll;
  "super_each", SuperEach;
  "auto", Auto;
]

let unif_conv = Cmdliner.Arg.enum unif_list

(* Unification parameters *)
let rigid_depth () =
  !rigid_max_depth + (Stats.current_round () / !rigid_round_incr)

(* Assumed formula parsing *)
(* ************************************************************************ *)

type state = {
  mutable true_preds : Expr.term list;
  mutable false_preds : Expr.term list;
  mutable equalities : (Expr.term * Expr.term) list;
  mutable inequalities : (Expr.term * Expr.term) list;
  mutable formulas : Expr.formula list;
}

let empty_st () = {
  true_preds = [];
  false_preds = [];
  equalities = [];
  inequalities = [];
  formulas = [];
}

let top = function
  | { Expr.term = Expr.App (f, _, _) } -> Some f
  | _ -> None

(* Folding over terms to unify *)
let fold_diff f start st =
  let acc = List.fold_left (fun acc (a, b) -> f acc a b) start st.inequalities in
  List.fold_left (fun acc' p ->
      List.fold_left (fun acc'' notp  ->
          if CCOpt.equal Expr.Id.equal (top p) (top notp) then
            f acc'' p notp
          else
            acc''
        ) acc' st.false_preds
    ) acc st.true_preds

let debug_st ~section n st =
  Util.debug ~section n "Found : %d true preds, %d false preds, %d equalities, %d inequalities"
    (List.length st.true_preds) (List.length st.false_preds) (List.length st.equalities) (List.length st.inequalities);
  List.iter (fun (a, b) -> Util.debug ~section n " |- %a == %a" Expr.Debug.term a Expr.Debug.term b) st.equalities;
  List.iter (fun (a, b) -> Util.debug ~section n " |- %a <> %a" Expr.Debug.term a Expr.Debug.term b) st.inequalities;
  List.iter (fun p -> Util.debug ~section n " |- %a: %a" Expr.Debug.formula Expr.Formula.f_true Expr.Debug.term p) st.true_preds;
  List.iter (fun p -> Util.debug ~section n " |- %a: %a" Expr.Debug.formula Expr.Formula.f_false Expr.Debug.term p) st.false_preds

let parse_aux res = function
  | { Expr.formula = Expr.Pred p } as f ->
    res.formulas <- f :: res.formulas;
    res.true_preds <- p :: res.true_preds
  | { Expr.formula = Expr.Not { Expr.formula = Expr.Pred p } } as f ->
    res.formulas <- f :: res.formulas;
    res.false_preds <- p :: res.false_preds
  | { Expr.formula = Expr.Equal (a, b) } as f ->
    if not (Expr.Term.equal a b) then begin
      res.formulas <- f :: res.formulas;
      res.equalities <- (a, b) :: res.equalities
    end
  | { Expr.formula = Expr.Not { Expr.formula = Expr.Equal (a, b) } } as f ->
    res.formulas <- f :: res.formulas;
    res.inequalities <- (a, b) :: res.inequalities
  | _ -> ()

let parse_slice iter =
  let res = empty_st () in
  iter (parse_aux res);
  res

(* Meta variables *)
(* ************************************************************************ *)

let metas = H.create 128

let get_nb_metas f =
  try
    H.find metas f
  with Not_found ->
    let i = ref 0 in
    H.add metas f i;
    i

let iter f = H.iter (fun e _ -> f e) metas

(* Proofs *)
let mk_proof_ty f metas =
  Dispatcher.mk_proof "meta" ~ty_args:([]) "ty"

let mk_proof_term f metas =
  Dispatcher.mk_proof "meta" ~term_args:([]) "term"

(* Meta generation & predicates storing *)
let do_formula =
  let aux = function
    | { Expr.formula = Expr.All (l, _, p) } as f ->
      let metas = List.map Expr.Term.of_meta (Expr.Meta.of_all f) in
      let subst = List.fold_left2 Expr.Subst.Id.bind Expr.Subst.empty l metas in
      let q = Expr.Formula.subst Expr.Subst.empty subst p in
      Dispatcher.push [Expr.Formula.neg f; q] (mk_proof_term f metas)
    | { Expr.formula = Expr.Not { Expr.formula = Expr.Ex (l, _, p) } } as f ->
      let metas = List.map Expr.Term.of_meta (Expr.Meta.of_all f) in
      let subst = List.fold_left2 Expr.Subst.Id.bind Expr.Subst.empty l metas in
      let q = Expr.Formula.subst Expr.Subst.empty subst p in
      Dispatcher.push [Expr.Formula.neg f; Expr.Formula.neg q] (mk_proof_term f metas)
    | { Expr.formula = Expr.AllTy (l, _, p) } as f ->
      let metas = List.map Expr.Ty.of_meta (Expr.Meta.of_all_ty f) in
      let subst = List.fold_left2 Expr.Subst.Id.bind Expr.Subst.empty l metas in
      let q = Expr.Formula.subst subst Expr.Subst.empty p in
      Dispatcher.push [Expr.Formula.neg f; q] (mk_proof_ty f metas)
    | { Expr.formula = Expr.Not { Expr.formula = Expr.ExTy (l, _, p) } } as f ->
      let metas = List.map Expr.Ty.of_meta (Expr.Meta.of_all_ty f) in
      let subst = List.fold_left2 Expr.Subst.Id.bind Expr.Subst.empty l metas in
      let q = Expr.Formula.subst subst Expr.Subst.empty p in
      Dispatcher.push [Expr.Formula.neg f; Expr.Formula.neg q] (mk_proof_ty f metas)
    | _ -> ()
  in function
    | ({ Expr.formula = Expr.Not { Expr.formula = Expr.ExTy _ } } as f)
    | ({ Expr.formula = Expr.Not { Expr.formula = Expr.Ex _ } } as f)
    | ({ Expr.formula = Expr.AllTy _ } as f)
    | ({ Expr.formula = Expr.All _ } as f) ->
      let i = get_nb_metas f in
      while !i < !meta_start do
        incr i;
        Util.debug ~section 5 "start meta (%d/%d) %a" !i !meta_start Expr.Debug.formula f;
        aux f
      done
    | _ -> ()

let do_meta_inst = function
  | { Expr.formula = Expr.All (l, _, p) } as f ->
    let i = get_nb_metas f in
    if !i < !meta_max then begin
      incr i;
      Util.debug ~section 5 "new_meta (%d/%d) : %a" !i !meta_max Expr.Debug.formula f;
      let metas = Expr.Meta.of_all f in
      let u = List.fold_left (fun s m -> Unif.bind_term s m (Expr.Term.of_meta m)) Unif.empty metas in
      if not (Inst.add ~delay:(delay !i) u) then assert false
    end
  | { Expr.formula = Expr.Not { Expr.formula = Expr.Ex (l, _, p) } } as f ->
    let i = get_nb_metas f in
    if !i < !meta_max then begin
      incr i;
      Util.debug ~section 5 "new_meta (%d/%d) : %a" !i !meta_max Expr.Debug.formula f;
      let metas = Expr.Meta.of_all f in
      let u = List.fold_left (fun s m -> Unif.bind_term s m (Expr.Term.of_meta m)) Unif.empty metas in
      if not (Inst.add ~delay:(delay !i) u) then assert false
    end
  | { Expr.formula = Expr.AllTy (l, _, p) } as f ->
    let i = get_nb_metas f in
    if !i < !meta_max then begin
      incr i;
      Util.debug ~section 5 "new_meta (%d/%d) : %a" !i !meta_max Expr.Debug.formula f;
      let metas = Expr.Meta.of_all_ty f in
      let u = List.fold_left (fun s m -> Unif.bind_ty s m (Expr.Ty.of_meta m)) Unif.empty metas in
      if not (Inst.add ~delay:(delay !i) u) then assert false
    end
  | { Expr.formula = Expr.Not { Expr.formula = Expr.ExTy (l, _, p) } } as f ->
    let i = get_nb_metas f in
    if !i < !meta_max then begin
      incr i;
      Util.debug ~section 5 "new_meta (%d/%d) : %a" !i !meta_max Expr.Debug.formula f;
      let metas = Expr.Meta.of_all_ty f in
      let u = List.fold_left (fun s m -> Unif.bind_ty s m (Expr.Ty.of_meta m)) Unif.empty metas in
      if not (Inst.add ~delay:(delay !i) u) then assert false
    end
  | _ -> assert false

(* Assuming function *)
let meta_assume = do_formula

(* Finding instanciations *)
(* ************************************************************************ *)

(* superposition limit *)
let sup_limit st =
  let n = fold_diff (fun n _ _ -> n + 1) 0 st in
  n * !sup_max_coef + !sup_max_const

(* Unification of predicates *)
let do_inst u = Inst.add ~score:(score u) u

let insts r l =
  let l = List.map Unif.fixpoint l in
  let l = CCList.flat_map Inst.split l in
  let l = List.map do_inst l in
  if List.exists CCFun.id l then begin
    decr r;
    log 10 "Waiting for %d other insts" !r;
    if !r <= 0 then raise Found_unif
  end

let single_inst u = insts (ref 1) [u]

let cache = Unif.Cache.create ()

let wrap_unif unif p notp =
  try unif p notp
  with Found_unif -> ()

let rec unif_f st = function
  | No_unif -> assert false
  | Simple ->
    Util.enter_prof unif_section;
    fold_diff (fun () -> wrap_unif (Unif.Cache.with_cache cache (
        Unif.Robinson.unify_term ~section:unif_section single_inst))) () st;
    Util.exit_prof unif_section
  | ERigid ->
    Util.enter_prof rigid_section;
    fold_diff (fun () -> wrap_unif (Rigid.unify ~max_depth:(rigid_depth ()) st.equalities single_inst)) () st;
    Util.exit_prof rigid_section
  | SuperEach ->
    Util.enter_prof sup_section;
    let t = Superposition.empty single_inst sup_section in
    let t = List.fold_left (fun acc (a, b) -> Superposition.add_eq acc a b) t st.equalities in
    let t = Superposition.solve t in
    fold_diff (fun () a b ->
        try let _ = Superposition.solve (Superposition.add_neq t a b) in ()
        with Found_unif -> ()
      ) () st;
    Util.exit_prof sup_section
  | SuperAll ->
    Util.enter_prof sup_section;
    let t = Superposition.empty (fun u -> insts (ref (sup_limit st)) [u]) sup_section in
    let t = List.fold_left (fun acc (a, b) -> Superposition.add_eq acc a b) t st.equalities in
    let t = fold_diff (fun acc a b -> Superposition.add_neq acc a b) t st in
    begin try
        let _ = Superposition.solve t in ()
      with Found_unif -> ()
    end;
    Util.exit_prof sup_section
  | Auto ->
    if st.equalities = [] then
      unif_f st Simple
    else
      unif_f st SuperAll

let find_all_insts : type ret. ret Dispatcher.msg -> ret option = function
  | Solver.Found_sat model ->
    (* Create new metas *)
    if !meta_incr then begin
      Util.debug 1 "New metas to generate (%d formulas to inspect)" (H.length metas);
      iter do_meta_inst
    end;
    (* Look at instanciation settings *)
    begin match !unif_setting with
      | No_unif -> ()
      | _ ->
        (* Analysing assummed formulas *)
        log 5 "Parsing input formulas";
        let st = parse_slice model in
        debug_st ~section 30 st;
        (* Search for instanciations *)
        log 5 "Applying unification";
        unif_f st !unif_setting
    end;
    Some Solver.Sat_ok
  | _ -> None

(* Extension registering *)
(* ************************************************************************ *)

let opts =
  let docs = Options.ext_sect in
  let inst =
    let doc = CCPrint.sprintf
        "Select unification method to use in order to find instanciations
       $(docv) may be %s." (Cmdliner.Arg.doc_alts_enum ~quoted:false unif_list) in
    Cmdliner.Arg.(value & opt unif_conv No_unif & info ["meta.find"] ~docv:"METHOD" ~docs ~doc)
  in
  let start =
    let doc = "Initial number of metavariables to generate for new formulas" in
    Cmdliner.Arg.(value & opt int 1 & info ["meta.start"] ~docv:"N" ~docs ~doc)
  in
  let max =
    let doc = "Maximum number of metas to generate" in
    Cmdliner.Arg.(value & opt int 10 & info ["meta.max"] ~docv:"N" ~docs ~doc)
  in
  let incr =
    let doc = "Set wether to generate new metas at each round (with delay)" in
    Cmdliner.Arg.(value & opt bool false & info ["meta.incr"] ~docs ~doc)
  in
  let delay =
    let doc = "Delay before introducing new metas" in
    Cmdliner.Arg.(value & opt (pair int int) (1, 3) & info ["meta.delay"] ~docs ~doc)
  in
  let heuristic =
    let doc = CCPrint.sprintf
        "Select heuristic to use when assigning scores to possible unifiers/instanciations.
       $(docv) may be %s" (Cmdliner.Arg.doc_alts_enum ~quoted:true heur_list) in
    Cmdliner.Arg.(value & opt heur_conv No_heuristic & info ["meta.heur"] ~docv:"HEUR" ~docs ~doc)
  in
  let sup_coef =
    let doc = "Affine coefficient for the superposition limit" in
    Cmdliner.Arg.(value & opt int 1 & info ["meta.sup.coef"] ~docs ~doc)
  in
  let sup_const =
    let doc = "Affine constant for the superposition limit" in
    Cmdliner.Arg.(value & opt int 0 & info ["meta.sup.const"] ~docs ~doc)
  in
  let rigid_depth =
    let doc = "Base to compute maximum depth when doing rigid unification." in
    Cmdliner.Arg.(value & opt int 2 & info ["meta.rigid.depth"] ~docv:"N" ~docs ~doc)
  in
  let rigid_incr =
    let doc = "Number of round to wait before increasing the depth of rigid unification." in
    Cmdliner.Arg.(value & opt int 3 & info ["meta.rigid.incr"] ~docv:"N" ~docs ~doc)
  in
  let set_opts heur start max inst incr delay s_coef s_const rigid_depth rigid_incr =
    heuristic_setting := heur;
    meta_start := start;
    meta_max := max;
    unif_setting := inst;
    meta_incr := incr;
    meta_delay := delay;
    sup_max_coef := s_coef;
    sup_max_const := s_const;
    rigid_max_depth := rigid_depth;
    rigid_round_incr := rigid_incr
  in
  Cmdliner.Term.(pure set_opts $ heuristic $ start $ max $ inst $ incr $ delay $ sup_coef $ sup_const $ rigid_depth $ rigid_incr)

let register () =
  Dispatcher.Plugin.register "meta" ~options:opts
    ~descr:"Generate meta variables for universally quantified formulas, and use unification to push
              possible instanciations to the 'inst' module."
    (Dispatcher.mk_ext
       ~handle:{Dispatcher.handle=find_all_insts}
       ~assume:meta_assume
       ~section ())

