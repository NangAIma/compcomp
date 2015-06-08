(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** * The whole compiler and its proof of semantic preservation *)

(** Libraries. *)
Require Import Coqlib.
Require Import Errors.
Require Import AST.
Require Import Smallstep.
(** Languages (syntax and semantics). *)
Require Csyntax.
Require Csem.
Require Cstrategy.
Require Cexec.
Require Clight.
Require Csharpminor.
Require Cminor.
Require CminorSel.
Require RTL.
Require LTL.
Require Linear.
Require Mach.
Require Asm_comp.
(** Translation passes. *)
Require Initializers.
Require SimplExpr.
Require SimplLocals.
Require Cshmgen.
Require Cminorgen.
Require SelectionNEW.
Require RTLgen.
Require Tailcall.
Require Inlining.
Require Renumber.
Require Constprop.
Require CSE.
Require Allocation.
Require Tunneling.
Require Linearize.
Require CleanupLabels.
Require Stacking.
Require Asmgen_comp.
(** Proofs of semantic preservation. *)
Require SimplExprproof.
Require SimplLocalsproof_comp.
Require Cshmgenproof_comp.
Require Cminorgenproof_comp.
Require Selectionproof_comp.
Require RTLgenproof_comp.
Require Tailcallproof_comp.
Require Inliningproof_comp.
Require Renumberproof_comp.
Require Constpropproof_comp.
Require CSEproof_comp.
Require Allocproof_comp.
Require Tunnelingproof_comp.
Require Linearizeproof_comp.
Require CleanupLabelsproof_comp.
Require Stackingproof_comp.
Require Asmgenproof_comp.

(** Pretty-printers (defined in Caml). *)
Parameter print_Clight: Clight.program -> unit.
Parameter print_Cminor: Cminor.program -> unit.
Parameter print_RTL: RTL.program -> unit.
Parameter print_RTL_tailcall: RTL.program -> unit.
Parameter print_LTL: LTL.program -> unit.
Parameter print_Mach: Mach.program -> unit.

Open Local Scope string_scope.

(** * Composing the translation passes *)

(** We first define useful monadic composition operators,
    along with funny (but convenient) notations. *)

Definition apply_total (A B: Type) (x: res A) (f: A -> B) : res B :=
  match x with Error msg => Error msg | OK x1 => OK (f x1) end.

Definition apply_partial (A B: Type)
                         (x: res A) (f: A -> res B) : res B :=
  match x with Error msg => Error msg | OK x1 => f x1 end.

Notation "a @@@ b" :=
   (apply_partial _ _ a b) (at level 50, left associativity).
Notation "a @@ b" :=
   (apply_total _ _ a b) (at level 50, left associativity).

Definition print {A: Type} (printer: A -> unit) (prog: A) : A :=
  let unused := printer prog in prog.

(** We define three translation functions: one starting with a C program, one
  with a Cminor program, one with an RTL program.  The three translations
  produce Asm programs ready for pretty-printing and assembling. *)

Definition transf_rtl_program (f: RTL.program) : res Asm_comp.program :=
   OK f
   @@ print print_RTL
   @@ Tailcall.transf_program
   @@ print print_RTL_tailcall
  @@@ Inlining.transf_program
   @@ Renumber.transf_program
(*   @@ print print_RTL_inline*)
(* (*TODO:*)  @@ Constprop.transf_program*)
   @@ Renumber.transf_program
(*   @@ print print_RTL_constprop*)
  @@@ CSE.transf_program
(*   @@ print print_RTL_cse*)
  @@@ Allocation.transf_program
   @@ print print_LTL
   @@ Tunneling.tunnel_program
  @@@ Linearize.transf_program
   @@ CleanupLabels.transf_program
  @@@ Stacking.transf_program
   @@ print print_Mach
  @@@ Asmgen_comp.transf_program.

Definition transf_cminor_program (p: Cminor.program) : res Asm_comp.program :=
   OK p
   @@ print print_Cminor
  @@@ SelectionNEW.sel_program
  @@@ RTLgen.transl_program
  @@@ transf_rtl_program.

Definition transf_clight_program (p: Clight.program) : res Asm_comp.program :=
  OK p 
   @@ print print_Clight
  @@@ SimplLocals.transf_program
  @@@ Cshmgen.transl_program
  @@@ Cminorgen.transl_program
  @@@ transf_cminor_program.

Definition transf_c_program (p: Csyntax.program) : res Asm_comp.program :=
  OK p 
  @@@ SimplExpr.transl_program
  @@@ transf_clight_program.

(** Force [Initializers] and [Cexec] to be extracted as well. *)

Definition transl_init := Initializers.transl_init.
Definition cexec_do_step := Cexec.do_step.

(** The following lemmas help reason over compositions of passes. *)

Lemma print_identity:
  forall (A: Type) (printer: A -> unit) (prog: A),
  print printer prog = prog.
Proof.
  intros; unfold print. auto.
Qed.

Lemma compose_print_identity:
  forall (A: Type) (x: res A) (f: A -> unit), 
  x @@ print f = x.
Proof.
  intros. destruct x; simpl. rewrite print_identity. auto. auto. 
Qed.

Lemma fst_transform_globdef_eq A B V (f : A -> B) (gv : ident*globdef A V) :
  fst (transform_program_globdef f gv) = fst gv.
Proof.
destruct gv; destruct g; auto.
Qed.

Lemma map_fst_transform_globdef_eq A B V (f : A -> B) (l : list (ident*globdef A V)) :
  map fst (map (transform_program_globdef f) l) = map fst l.
Proof.
induction l; auto.
simpl; rewrite fst_transform_globdef_eq, IHl; auto.
Qed.

Lemma map_fst_transf_globdefs_eq A B V W (f : A -> res B) (g : V -> res W) 
            p (l : list (ident*globdef B W)) :
  transf_globdefs f g (prog_defs p) = OK l ->
  map fst (prog_defs p) = map fst l.
Proof.
generalize (prog_defs p); intros l0.
revert l0 l.
induction l0; inversion 1; subst; auto.
simpl in *.
destruct a.
destruct g0.
destruct (f f0); try solve[inv H].
monadInv H.
monadInv H1.
simpl in *.
f_equal.
solve[rewrite <-IHl0; auto].
destruct (transf_globvar g v); try solve[inv H].
monadInv H.
monadInv H1.
simpl.
f_equal.
solve[rewrite <-IHl0; auto].
Qed.

Lemma list_norepet_transform F V (p : AST.program F V) G (f : F -> G) :
  list_norepet (map fst (prog_defs p)) <-> 
  list_norepet (map fst (prog_defs (transform_program f p))).
Proof.
unfold transform_program; simpl.
rewrite map_fst_transform_globdef_eq; split; auto.
Qed.

Lemma list_norepet_transform_partial F V (p : AST.program F V) G (f : F -> res G) p' :
  transform_partial_program f p = OK p' ->
  list_norepet (map fst (prog_defs p)) ->
  list_norepet (map fst (prog_defs p')).
Proof.
unfold transform_partial_program, transform_partial_program2, bind.
case_eq (transf_globdefs f (fun v : V => OK v) (prog_defs p)); try inversion 2.
erewrite map_fst_transf_globdefs_eq; eauto.
Qed.

Lemma TransformLNR_partial: forall {A B V} f p q
 (LNR: list_norepet (map fst (prog_defs p)))
 (TPP: @transform_partial_program A B V f p = OK q),
 list_norepet (map fst (prog_defs q)).
Proof. intros; eapply list_norepet_transform_partial; eauto. Qed.

Lemma TransformLNR_partial2: forall {A B V W} f g p q
 (LNR: list_norepet (map fst (prog_defs p)))
 (TPP: @transform_partial_program2 A B V W f g p = OK q),
 list_norepet (map fst (prog_defs q)).
Proof. 
unfold transform_partial_program2, bind; intros; revert TPP.
case_eq (transf_globdefs f g (prog_defs p)); inversion 2; subst; simpl.
apply map_fst_transf_globdefs_eq in H; rewrite H in LNR; auto.
Qed.

Lemma TransformLNR: forall {A B V} f p 
 (LNR: list_norepet (map fst (prog_defs p))),
 list_norepet (map fst (prog_defs (@transform_program A B V f p))).
Proof. intros; erewrite <-list_norepet_transform; eauto. Qed.

(** * Semantic preservation *)

Require Import simulations.
Require Import simulations_trans.
Require Import Globalenvs.
Require Import Cminor_eff.
Require Import Clight_eff.
Require Import RTL_eff.
Require Import Asm_eff.

(** See CompCert's backend/Selectionproof.v, in which the same assumption is
  made (l. 690).  We pull it out to the top-level because all of our language semantics
  are now parameterized by [hf], in order to properly classify I64 helper
  functions as nonobservable. *)

Parameter hf : I64Helpers.helper_functions.
Axiom HelpersOK: I64Helpers.get_helpers = OK hf.

(** Prove the existence of a structured simulation between RTL and Asm. *)

Theorem transf_rtl_program_correct:
  forall p tp (LNR: list_norepet (map fst (prog_defs p))),
  transf_rtl_program p = OK tp ->
  SM_simulation.SM_simulation_inject (rtl_eff_sem hf) (Asm_eff_sem hf)
      (Genv.globalenv p) (Genv.globalenv tp).
Proof.
  intros. 
  unfold transf_rtl_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H. 
  set (p1 := Tailcall.transf_program p) in *.
  destruct (Inlining.transf_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  set (p3 := Renumber.transf_program p2) in *.
(*  set (p4 := Constprop.transf_program p3) in *.*)
  set (p5 := Renumber.transf_program p3) in *.
  destruct (CSE.transf_program p5) as [p6|] eqn:?; simpl in H; try discriminate.
  destruct (Allocation.transf_program p6) as [p7|] eqn:?; simpl in H; try discriminate.
  set (p8 := Tunneling.tunnel_program p7) in *.
  destruct (Linearize.transf_program p8) as [p9|] eqn:?; simpl in H; try discriminate.
  set (p10 := CleanupLabels.transf_program p9) in *.
  destruct (Stacking.transf_program p10) as [p11|] eqn:?; simpl in H; try discriminate.
  eapply eff_sim_trans.
    eapply Tailcallproof_comp.transl_program_correct. 
  eapply TransformLNR in LNR.
  eapply eff_sim_trans.
    eapply Inliningproof_comp.transl_program_correct.
    unfold p1 in Heqr. exact Heqr.
    apply LNR.  
  eapply TransformLNR_partial with (q:=p2) in LNR.  2: eauto.
  eapply eff_sim_trans.
  eapply Renumberproof_comp.transl_program_correct.
  eapply eff_sim_trans.
(*  eapply Constpropproof_comp.transl_program_correct.
  eapply eff_sim_trans.*)
  eapply Renumberproof_comp.transl_program_correct.
  eapply eff_sim_trans.
    eapply CSEproof_comp.transl_program_correct.
    unfold p5, (*p4,*) p3 in Heqr0. exact Heqr0.
  eapply eff_sim_trans.
    eapply Allocproof_comp.transl_program_correct.
    instantiate (1:=p7). auto. 
  eapply eff_sim_trans.
    eapply Tunnelingproof_comp.transl_program_correct.
  eapply eff_sim_trans.
    eapply Linearizeproof_comp.transl_program_correct. 
    eassumption. 
  eapply eff_sim_trans.
    eapply CleanupLabelsproof_comp.transl_program_correct.
  eapply eff_sim_trans.
  eapply Stackingproof_comp.transl_program_correct.
  
    eexact Asmgenproof_comp.return_address_exists. eassumption.
    eapply TransformLNR. 
    eapply TransformLNR_partial. 2: eassumption. 
    eapply TransformLNR. 
    eapply TransformLNR_partial. 2: eassumption. 
    eapply TransformLNR_partial. 2: eassumption. 
    (*eapply TransformLNR.*) eapply TransformLNR. eapply TransformLNR.  assumption.

    apply Asmgenproof_comp.transl_program_correct. 
    eassumption.
Qed.

(** Prove the existence of a structured simulation between Cminor and Asm, 
    relying on [transf_rtl_program_correct] above. *)

Theorem transf_cminor_program_correct:
  forall p tp (LNR: list_norepet (map fst (prog_defs p))),
  transf_cminor_program p = OK tp ->
  SM_simulation.SM_simulation_inject (cmin_eff_sem hf) (Asm_eff_sem hf)
      (Genv.globalenv p) (Genv.globalenv tp).
Proof.
  intros.
  unfold transf_cminor_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H. 
  destruct (SelectionNEW.sel_program p) as [p1|] eqn:?; simpl in H; try discriminate.
  destruct (RTLgen.transl_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  eapply eff_sim_trans.
    eapply Selectionproof_comp.transl_program_correct.
     apply BuiltinEffects.get_helpers_correct. apply HelpersOK.
  unfold SelectionNEW.sel_program in Heqr. unfold bind in Heqr.
     rewrite HelpersOK in Heqr. inv Heqr. 
  eapply TransformLNR in LNR.   
  eapply eff_sim_trans.
    eapply RTLgenproof_comp.transl_program_correct.
     eassumption.
  eapply TransformLNR_partial in LNR.  
    eapply transf_rtl_program_correct; try eassumption. 
    unfold  RTLgen.transl_program in Heqr0. eassumption. 
Qed.

(** Prove the existence of a structured simulation between Clight and Asm, 
    relying on [transf_cminor_program_correct] above. *)

(** This is Theorem 3, Compiler Correctness in on pg. 11 (Clight->x86 Asm). *)

Theorem transf_clight_program_correct:
  forall p tp (LNR: list_norepet (map fst (prog_defs p))),
  transf_clight_program p = OK tp ->
  SM_simulation.SM_simulation_inject (CL_eff_sem1 hf) 
      (Asm_eff_sem hf)
      (Genv.globalenv p) (Genv.globalenv tp).
Proof.
  intros.
  unfold transf_clight_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H. 
  destruct (SimplLocals.transf_program p) as [p1|] eqn:?; simpl in H; try discriminate.
  destruct (Cshmgen.transl_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  destruct (Cminorgen.transl_program p2) as [p3|] eqn:?; simpl in H; try discriminate.
  eapply eff_sim_trans.
    eapply SimplLocalsproof_comp.transl_program_correct. eassumption.
     eassumption. 
  eapply TransformLNR_partial in LNR. 2: eauto.
  eapply eff_sim_trans.
    eapply Cshmgenproof_comp.transl_program_correct. 
    eassumption.
    eassumption.
  eapply TransformLNR_partial2 in LNR; eauto.
  eapply eff_sim_trans.
    eapply Cminorgenproof_comp.transl_program_correct. 
    eassumption.
    eassumption.
  eapply TransformLNR_partial in LNR. 2: eauto.
  eapply transf_cminor_program_correct; eassumption. 
Qed.

(** Prove that global symbols are preserved by compilation. *)

Theorem transf_rtl_program_preserves_syms:
  forall p tp, 
  transf_rtl_program p = OK tp ->
  forall s : ident,
  Genv.find_symbol (Genv.globalenv tp) s =
  Genv.find_symbol (Genv.globalenv p) s.
Proof.
  intros. 
  unfold transf_rtl_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H.
  
  set (p1 := Tailcall.transf_program p) in *.
  destruct (Inlining.transf_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  set (p3 := Renumber.transf_program p2) in *.
(*  set (p4 := Constprop.transf_program p3) in *.*)
  set (p5 := Renumber.transf_program p3) in *.
  destruct (CSE.transf_program p5) as [p6|] eqn:?; simpl in H; try discriminate.
  destruct (Allocation.transf_program p6) as [p7|] eqn:?; simpl in H; try discriminate.
  set (p8 := Tunneling.tunnel_program p7) in *.
  destruct (Linearize.transf_program p8) as [p9|] eqn:?; simpl in H; try discriminate.
  set (p10 := CleanupLabels.transf_program p9) in *.
  destruct (Stacking.transf_program p10) as [p11|] eqn:?; simpl in H; try discriminate.
  
  rewrite <- (Tailcallproof_comp.symbols_preserved p s).
  unfold p1 in *.
  erewrite <- (Inliningproof_comp.symbols_preserved); try eauto. clear Heqr.
  erewrite <- (Renumberproof_comp.symbols_preserved); try eauto.
  unfold p5, (*p4,*) p3 in *.
(*  erewrite <- (Constpropproof_comp.symbols_preserved); try eauto.*)
  erewrite <- (Renumberproof_comp.symbols_preserved); try eauto.
  erewrite <- (CSEproof_comp.symbols_preserved); try eauto. clear Heqr0.
  erewrite <- (Allocproof_comp.symbols_preserved); try eauto. clear Heqr1.
  unfold p8 in *.
  erewrite <- (Tunnelingproof_comp.symbols_preserved); try eauto.
  erewrite <- (Linearizeproof_comp.symbols_preserved); try eauto. clear Heqr2.
  erewrite <- (CleanupLabelsproof_comp.symbols_preserved); try eauto.
  erewrite <- (Stackingproof_comp.symbols_preserved); try eauto. 
  erewrite <- (Asmgenproof_comp.symbols_preserved); try eauto. 
Qed.

Theorem transf_cminor_program_preserves_syms:
  forall p tp,
  transf_cminor_program p = OK tp ->
  forall s : ident,
  Genv.find_symbol (Genv.globalenv tp) s =
  Genv.find_symbol (Genv.globalenv p) s.
Proof.
  intros.
  unfold transf_cminor_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H. 
  destruct (SelectionNEW.sel_program p) as [p1|] eqn:?; simpl in H; try discriminate.
  destruct (RTLgen.transl_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  apply transf_rtl_program_preserves_syms with (s:=s) in H; rewrite H.
  apply RTLgenproof_comp.symbols_preserved with (s:=s) in Heqr0; rewrite Heqr0.
  generalize (Selectionproof_comp.symbols_preserved p hf s); intros H2.
  revert Heqr; unfold SelectionNEW.sel_program, bind.
  rewrite HelpersOK; inversion 1; rewrite H2; auto.
Qed.

Theorem transf_clight_program_preserves_syms:
  forall p tp,
  transf_clight_program p = OK tp ->
  forall s : ident,
  Genv.find_symbol (Genv.globalenv tp) s =
  Genv.find_symbol (Genv.globalenv p) s.
Proof.
  intros.
  unfold transf_clight_program in H.
  repeat rewrite compose_print_identity in H.
  simpl in H. 
  destruct (SimplLocals.transf_program p) as [p1|] eqn:?; simpl in H; try discriminate.
  destruct (Cshmgen.transl_program p1) as [p2|] eqn:?; simpl in H; try discriminate.
  destruct (Cminorgen.transl_program p2) as [p3|] eqn:?; simpl in H; try discriminate.
  apply SimplLocalsproof_comp.symbols_preserved with (s := s) in Heqr.
  apply Cshmgenproof_comp.symbols_preserved with (s := s) in Heqr0.
  apply CminorgenproofRestructured.symbols_preserved with (s := s) in Heqr1.
  apply transf_cminor_program_preserves_syms with (s := s) in H.
  rewrite H, Heqr1, Heqr0, Heqr; auto.
Qed.