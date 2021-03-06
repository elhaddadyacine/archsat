(* This file is free software, part of Archsat. See file "LICENSE" for more details. *)

exception Abort of string * string
exception Extension_not_found of string * string * string list

module type K = sig
  type t

  val neutral : t

  val merge : high:t -> low:t -> t

  val section : Section.t

end

module type S = Extension_intf.S

module Make(E: K) : S with type ext = E.t

