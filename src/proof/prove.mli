
(** Proving utilities

    Wrappers for proof type-defs, definitions, axioms,
    and general global state. *)

(** {2 Managings proof state} *)

val init : Options.opts -> unit -> unit
(** Initialize the formatters for proof output. *)

val declare_ty :
  ?loc:Dolmen.ParseLocation.t -> Options.proof_options -> Expr.Id.TyCstr.t -> unit
(** Declare a type constructor. *)

val declare_term :
  ?loc:Dolmen.ParseLocation.t -> Options.proof_options -> Expr.Id.Const.t -> unit
(** Declare a new constant symbol. *)

val declare_hyp :
  ?loc:Dolmen.ParseLocation.t -> Options.proof_options -> Dolmen.Id.t -> Expr.formula -> Term.id
(** Declare a new hyp. *)

val declare_goal :
  ?loc:Dolmen.ParseLocation.t -> Options.proof_options -> Dolmen.Id.t -> Expr.formula -> Term.id
(** Declare a goal. *)

val output_proof : Options.proof_options -> Solver.proof -> unit
(** Output the proof on all relevant files according to options. *)


