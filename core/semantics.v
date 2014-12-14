(*CompCert imports*)
Require Import Events.
Require Import Memory.
Require Import Coqlib.
Require Import Values.
Require Import Maps.
Require Import Integers.
Require Import AST. 
Require Import Globalenvs.
Require Import Axioms.

Require Import mem_lemmas.
Require Import gen_genv.

(** * Interaction Semantics *)

(** NOTE: In the code, we call interaction semantics [CoreSemantics]. *)

(** The [G] type parameter is the type of global environments, the type
   [C] is the type of core states, and the type [E] is the type of
   extension requests. *)

(** [at_external] gives a way to determine when the sequential
   execution is blocked on an extension call, and to extract the
   data necessary to execute the call. *)
   
(** [after_external] give a way to inject the extension call results
   back into the sequential state so execution can continue. *)

(** [initial_core] produces the core state corresponding to an entry
   point of a module.  The arguments are the genv, a pointer to the
   function to run, and the arguments for that function. *)

(** [halted] indicates when a program state has reached a halted state,
   and what it's exit code/return value is when it has reached such
   a state. *)

(** [corestep] is the fundamental small-step relation for the
   sequential semantics. *)

(** The remaining properties give basic sanity properties which constrain
   the behavior of programs. *)
(** -1 a state cannot be both blocked on an extension call and also step, *)
(** -2 a state cannot both step and be halted, and *)
(** -3 a state cannot both be halted and blocked on an external call. *)

(* V is the type of values transmitted between cores and the memory. *)
Record CoreSemantics {G C M V T : Type} : Type :=
  { initial_core : G -> V -> list V -> option C
  ; at_external : C -> option (g_external_function T * g_signature T * list V)
  ; after_external : option V -> C -> option C
  ; halted : C -> option V
  ; corestep : G -> C -> M -> C -> M -> Prop

  ; corestep_not_at_external: 
      forall ge m q m' q', corestep ge q m q' m' -> at_external q = None
  ; corestep_not_halted: 
      forall ge m q m' q', corestep ge q m q' m' -> halted q = None
  ; at_external_halted_excl: 
      forall q, at_external q = None \/ halted q = None }.

Implicit Arguments CoreSemantics [].

(** * Cooperating Interaction Semantics *)

(** Cooperating semantics impose additional constraints; in particular, they
   specialize interaction semantics to CompCert memories and require that the
   memories produced by coresteps are [forward] wrt. the initial memory. See
   [core/mem_lemmas.v] for the defn. of [mem_forward]. *)

Record CoopCoreSem {G C} :=
  { coopsem :> CoreSemantics G C mem val typ
  ; corestep_fwd : 
      forall g c m c' m' (CS: corestep coopsem g c m c' m'), 
      mem_forward m m' }.

Implicit Arguments CoopCoreSem [].
