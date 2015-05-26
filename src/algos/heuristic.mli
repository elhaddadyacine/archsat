
(** Heuristics about unifiers.
    This module implements heuristics to give scores to instantiations
    based on the status of expressions. Highly experimental. *)

val goal_directed : Unif.t -> int
(** Gives higher scores to substitutions in wich terms are mapped
    to expressions coming from goals. *)

