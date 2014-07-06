Require Import pos.
Require Import compcert_linking.
Require Import linking_proof.
Require Import context_equiv.
Require Import effect_simulations.
Require Import nucular_semantics.
Require Import wholeprog_lemmas.
Require Import Asm_nucular.
Require Import CompositionalCompiler.

(* ssreflect *)

Require Import ssreflect ssrbool ssrfun seq eqtype fintype.
Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(** Apply the contextual equivalence functor from
   linking/context_equiv.v to to linking/linking_proof.v.*)
Module CE := ContextEquiv LinkingSimulation.

Section CompositionalComplements.

Notation Clight_module := (program Clight.fundef Ctypes.type).
Notation Asm_module := (AsmEFF.program).

(** [N] is the number of source/target modules. *)

Variable N : pos.
Variable source_modules : 'I_N -> Clight_module.
Variable target_modules : 'I_N -> Asm_module.
Variable plt : ident -> option 'I_N.

Definition mk_src_sem (p : Clight_module) :=
  let ge := Genv.globalenv p in 
  @Modsem.mk Clight.fundef Ctypes.type ge Clight_coop.CL_core (Clight_eff.CL_eff_sem1 hf).

Definition mk_tgt_sem (tp : Asm_module) :=
  let tge := Genv.globalenv tp in
  @Modsem.mk AsmEFF.fundef unit tge Asm_coop.state (Asm_eff.Asm_eff_sem hf).

Definition sems_S (ix : 'I_N) := mk_src_sem (source_modules ix).
Definition sems_T (ix : 'I_N) := mk_tgt_sem (target_modules ix).

(** [ge_top] ensures that the globalenvs for the modules agree on the
 set of global blocks. *)

Variable ge_top : ge_ty.
Variable domeq_S : forall ix : 'I_N, genvs_domain_eq ge_top (sems_S ix).(Modsem.ge).
Variable domeq_T : forall ix : 'I_N, genvs_domain_eq ge_top (sems_T ix).(Modsem.ge). 

(** The (deterministic) context [C]: *)

Variable C : Modsem.t.   
Variable sim_C : 
  SM_simulation.SM_simulation_inject 
    C.(Modsem.sem) C.(Modsem.sem) C.(Modsem.ge) C.(Modsem.ge).
Variable nuke_C : Nuke_sem.t (Modsem.sem C).
Variable domeq_C : genvs_domain_eq ge_top C.(Modsem.ge).
Variable det_C : corestep_fun (Modsem.sem C).

(** [NOTE: RC] [CE.linker_S] ensures that both the context [C] the
  source modules [sems_S] are reach-closed. See file
  linking/context_equiv.v. *)

Notation source_linked_semantics := (CE.linker_S sems_S plt C).
Notation target_linked_semantics := (CE.linker_T sems_T plt C).

Lemma asm_modules_nucular (ix : 'I_N) : Nuke_sem.t (Modsem.sem (sems_T ix)).
Proof. solve[apply Asm_is_nuc]. Qed.

(** Each Clight module is independently translated to the
 corresponding module in x86 assembly. The [init] and [lnr] conditions
 ensure that each module is well-formed (for example, no module
 defines the same function twice). *)

Variable transf : forall ix : 'I_N, 
  transf_clight_program (source_modules ix) = Errors.OK (target_modules ix).
Variable init : forall ix : 'I_N, 
  {m0 | Genv.init_mem (source_modules ix) = Some m0}.
Variable lnr : forall ix : 'I_N, 
  list_norepet (map fst (prog_defs (source_modules ix))).

Lemma modules_inject (ix : 'I_N) : 
  SM_simulation.SM_simulation_inject 
    (Modsem.sem (sems_S ix)) (Modsem.sem (sems_T ix)) 
    (Modsem.ge (sems_S ix)) (Modsem.ge (sems_T ix)).
Proof.
generalize (transf ix); intros H.
generalize (init ix). intros [m0 H2].
eapply transf_clight_program_correct in H; eauto.
Qed.

(** The entry point for the linked program: *)

Variable main : Values.val.

Notation lifted_sim := 
  (CE.lifted_sim asm_modules_nucular plt modules_inject domeq_S domeq_T 
     sim_C domeq_C nuke_C main).

(** Starting from matching source--target states, the source/target
 programs equiterminate when linked with [C], assuming the source
 linked program is safe and reach-closed (see [NOTE: RC] above), and
 the target linked program is deterministic. *)

Theorem context_equiv  
  (target_det : core_semantics_lemmas.corestep_fun target_linked_semantics) 
  cd mu l1 m1 l2 m2 
  (source_safe : forall n, closed_safety.safeN source_linked_semantics ge_top n l1 m1) 
  (match12 : Wholeprog_simulation.match_state lifted_sim cd mu l1 m1 l2 m2) :
  (terminates source_linked_semantics ge_top l1 m1 
   <-> terminates target_linked_semantics ge_top l2 m2).
Proof. eapply CE.context_equiv; eauto. Qed.

End CompositionalComplements.
  
