
(** Base Tactics for logic.

    This module defines a good quantity of base tactics
    (i.e functions that operate on proof positions) related
    used in most proofs. *)

open Proof

(** {2 Convenience functions} *)

val extract_open : Proof.pos -> Proof.sequent
(** Extract the sequent from an open proof position. *)

(** {2 Preludes} *)

val classical : Prelude.t
(** The prelude requiring classical logic *)


(** {2 Some terms} *)

val true_proof : Term.t
(** The term proving [true]. *)

(** {2 Simple tactics} *)

val ctx : (Proof.sequent -> (pos, 'a) tactic) -> (pos, 'a) tactic
(** Wrapper around tactics to access environment (and use it to compute
    parameters for the tactic). *)

val intro : string -> (pos, pos) tactic
val introN : string -> int -> (pos, pos) tactic
(** Introduction tactic. The string given is used as prefix
    for the name of the newly introduced hypothesis. *)

val cut :
  ?weak:bool ->
  f:((pos, unit) tactic) ->
  string -> Term.t -> (pos, Term.id * pos) tactic
(** Cut/assert a given term (using the string as prefix for the env),
    and use the given function to prove the asserted term. *)

val exact  : Prelude.t list -> Term.t -> (pos, unit) tactic
val apply1 : Prelude.t list -> Term.t -> (pos, pos) tactic
val apply2 : Prelude.t list -> Term.t -> (pos, pos * pos) tactic
val apply3 : Prelude.t list -> Term.t -> (pos, pos * pos * pos) tactic
(** Fixed arity applications. *)

val split :
  left:((pos, unit) tactic) ->
  right:((pos, unit) tactic) ->
  (pos * pos, unit) tactic
(** Convenience operator for operating on a pair of positions. *)

val split3 :
  first:((pos, unit) tactic) ->
  second:((pos, unit) tactic) ->
  third:((pos, unit) tactic) ->
  (pos * pos * pos, unit) tactic
(** Convenience operators for mainpulating multiple positions at a time. *)


(** {2 Standard tactics} *)

val trivial : (pos, bool) tactic
(** Try and find the goal in the environment.
    Returns true if the branch has been closed, else returns false. *)

val exfalso : (pos, pos) tactic
(** Apply exfalso, if needed, in order to get a sequent of the form
    Gamm |- False. *)

val absurd : Term.t -> (pos, unit) tactic
(** Given a term [t], find [t] and its negation in the environment
    in order to close the branch, possibly applying exfalso if needed. *)

val or_elim :
  f:(Term.t -> (pos, unit) tactic) ->
  Term.t -> (pos, unit) tactic
(** Eliminate a disjunction present in the environment. *)

val and_elim : Term.t -> (pos, pos) tactic
(** Eliminate a conjunction, introducing its individual terms in the env. *)

val not_not_elim : string -> Term.t -> (pos, pos) tactic
(** Given a goal of the form [False], and with [~ ~ t] in the env,
    introduce [t] in the environment. *)

val normalize : string -> Term.t -> (pos, pos) tactic
(** Try and apply doulbe negation elimination to introduce the given term,
    if it is not already present. *)


(** {2 Classical tactics} *)

val nnpp : (pos, pos) tactic
(** Applies nnpp *only if necessary*, to get at the end a
    pos to a sequent of the form Gamma |- False.
    The resulting proof may, or may *not* be classical. *)


(** {2 Weak clause translation} *)

val clause_type : Term.t list -> Term.t
(** Computes the weak clause encoding of the given list of terms,
    i.e. [~ l_1 -> ... -> ~ l_n -> False]. *)

val resolve_clause : Term.id -> Term.id -> Term.t list -> Term.t
(** Compute the resolution of two clauses. *)

val resolve : Term.id -> Term.id -> Term.t list -> (pos, Term.id * pos) tactic
(** Resolution of clauses *)
