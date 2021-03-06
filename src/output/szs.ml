(* This file is free software, part of Archsat. See file "LICENSE" for more details. *)

(* Misc functions *)
(* ************************************************************************ *)

let prelude _ = ""

(* Output functions *)
(* ************************************************************************ *)

let print_res opt fmt status =
  Format.fprintf fmt "%% SZS status %s for %s"
    status (Options.input_to_string Options.(opt.input.file))

let print_status opt fmt status =
  Format.fprintf fmt "%a@." (print_res opt) status

let print_sat fmt opt = print_status opt fmt "CounterSatisfiable"
let print_unsat fmt opt = print_status opt fmt "Theorem"
let print_unknown fmt opt = print_status opt fmt "Unknown"
let print_timeout fmt opt = print_status opt fmt "TimeOut"
let print_spaceout fmt opt = print_status opt fmt "MemoryOut"

let print_exn opt fmt = function
  | Options.Out_of_time -> print_status opt fmt "TimeOut"
  | Options.Out_of_space -> print_status opt fmt "MemoryOut"
  | _ -> Format.fprintf fmt "%a@." (print_res opt) "Error"

