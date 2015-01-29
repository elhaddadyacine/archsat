


val instanciations : Dispatcher.id ->
    (Expr.ty Expr.meta * Expr.term) list ->
    ((Expr.formula list) * Dispatcher.proof) list
(** Takes an id and a (partial) list of instanciations,
    and returns a list of clauses ready to be pushed,
    along with their proof indication *)

