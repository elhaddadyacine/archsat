(* This file is free software, part of Archsat. See file "LICENSE" for more details. *)
(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** hopefully more efficient (polynomial) implementation of LPO,
    following the paper "things to know when implementing LPO" by Löchner.
    We adapt here the implementation clpo6 with some multiset symbols (=) *)

(** recursive path ordering *)
let rec rpo6 ~prec s t =
  if Expr.Term.equal s t then Comparison.Eq else  (* equality test is cheap *)
    match s, t with
    (* Variables *)
    | { Expr.term = Expr.Var _ }, { Expr.term = Expr.Var _ } ->
      Comparison.Incomparable
    | _, { Expr.term = Expr.Var v } ->
      if Expr.Id.occurs_in_term v s then Comparison.Gt else Comparison.Incomparable
    | { Expr.term = Expr.Var v } , _ ->
      if Expr.Id.occurs_in_term v t then Comparison.Lt else Comparison.Incomparable
    (* Meta-variables *)
    | { Expr.term = Expr.Meta _ }, { Expr.term = Expr.Meta _ } ->
      Comparison.Incomparable
    | _, { Expr.term = Expr.Meta m } ->
      if Expr.Meta.occurs_in_term m s then Comparison.Gt else Comparison.Incomparable
    | { Expr.term = Expr.Meta m } , _ ->
      if Expr.Meta.occurs_in_term m t then Comparison.Lt else Comparison.Incomparable
    (* Application *)
    | { Expr.term = Expr.App (f, _, ss) }, { Expr.term= Expr.App (g, _, ts)} ->
      rpo6_composite ~prec s t f g ss ts

(* handle the composite cases *)
and rpo6_composite ~prec s t f g ss ts =
  match prec f g with
  | 0 -> cLMA ~prec s t ss ts  (* lexicographic subterm comparison *)
  | n when n > 0 -> cMA ~prec s ts
  | _ (* n < 0 *) -> Comparison.opp (cMA ~prec t ss)

(** try to dominate all the terms in ts by s; but by subterm property
      if some t' in ts is >= s then s < t=g(ts) *)
and cMA ~prec s ts = match ts with
  | [] -> Comparison.Gt
  | t::ts' ->
    (match rpo6 ~prec s t with
     | Comparison.Gt -> cMA ~prec s ts'
     | Comparison.Eq | Comparison.Lt -> Comparison.Lt
     | Comparison.Incomparable -> Comparison.opp (alpha ~prec ts' s))

(** lexicographic comparison of s=f(ss), and t=f(ts) *)
and cLMA ~prec s t ss ts = match ss, ts with
  | si::ss', ti::ts' ->
    (match rpo6 ~prec si ti with
     | Comparison.Eq -> cLMA ~prec s t ss' ts'
     | Comparison.Gt -> cMA ~prec s ts' (* just need s to dominate the remaining elements *)
     | Comparison.Lt -> Comparison.opp (cMA ~prec t ss')
     | Comparison.Incomparable -> cAA ~prec s t ss' ts'
    )
  | [], [] -> Comparison.Eq
  | _ -> assert false (* different length... *)

(** bidirectional comparison by subterm property (bidirectional alpha) *)
and cAA ~prec s t ss ts =
  match alpha ~prec ss t with
  | Comparison.Gt -> Comparison.Gt
  | Comparison.Incomparable -> Comparison.opp (alpha ~prec ts s)
  | _ -> assert false
(** if some s in ss is >= t, then s > t by subterm property and transitivity *)
and alpha ~prec ss t = match ss with
  | [] -> Comparison.Incomparable
  | s::ss' ->
    (match rpo6 ~prec s t with
     | Comparison.Eq | Comparison.Gt -> Comparison.Gt
     | Comparison.Incomparable | Comparison.Lt -> alpha ~prec ss' t)

let compare_terms ~prec (x, y) = rpo6 ~prec x y

let cache =
  CCCache.unbounded 4013
    ~hash:(fun (t, t') -> CCHash.combine2 (Expr.Term.hash t) (Expr.Term.hash t'))
    ~eq:(fun (t1, t2) (t1',t2') -> Expr.Term.equal t1 t1' && Expr.Term.equal t2 t2')

let compare x y =
  CCCache.with_cache cache (compare_terms ~prec:Expr.Id.compare) (x, y)

