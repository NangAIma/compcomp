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

Record CoreSemantics {G C M : Type} : Type :=
  { initial_core : G -> val -> list val -> option C
  ; at_external : C -> option (external_function * signature * list val)
  ; after_external : option val -> C -> option C
  ; halted : C -> option val
  ; corestep : G -> C -> M -> C -> M -> Prop

  ; corestep_not_at_external: 
      forall ge m q m' q', corestep ge q m q' m' -> at_external q = None
  ; corestep_not_halted: 
      forall ge m q m' q', corestep ge q m q' m' -> halted q = None
  ; at_external_halted_excl: 
      forall q, at_external q = None \/ halted q = None }.

Implicit Arguments CoreSemantics [].

Inductive mem_step m m' : Prop :=
    mem_step_storebytes: forall b ofs bytes,
       Mem.storebytes m b ofs bytes = Some m' -> mem_step m m'
  | mem_step_alloc: forall lo hi b',
       Mem.alloc m lo hi = (m',b') -> mem_step m m'
  | mem_step_freelist: forall l,
       Mem.free_list m l = Some m' -> mem_step m m'
  (*Some non-observable external calls are not a single alloc/free/store-step*)
  | mem_step_trans: forall m'',
       mem_step m m'' -> mem_step m'' m' -> mem_step m m'.


(* Memory semantics are CoreSemantics that are specialized to CompCert memories
   and evolve memory according to mem_step. Previous notions CoopCoreSem,
   and DecaySem are deprecated, but for now retained in file CoopCoreSem.v *)
Record MemSem {G C} :=
  { csem :> @CoreSemantics G C mem

  ; corestep_mem : forall g c m c' m' (CS: corestep csem g c m c' m'), mem_step m m'
  }.

Implicit Arguments MemSem [].