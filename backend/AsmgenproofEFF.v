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

(** Correctness proof for x86 generation: main proof. *)

Require Import Coqlib.
Require Import Errors.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Op.
Require Import Locations.
Require Import Mach.
Require Import Conventions.
Require Import AsmEFF.
Require Import AsmgenEFF.
Require Import Asmgenproof0EFF.
Require Import Asmgenproof1EFF.

Require Import Mach_coop.
Require Import Mach_eff.
Require Import Asm_coop.
Require Import Asm_eff.

Require Import mem_lemmas.
Require Import core_semantics.
Require Import core_semantics_lemmas.
Require Import effect_semantics.
Require Import StructuredInjections.
Require Import reach.
Require Import effect_simulations.
Require Import effect_properties.
Require Import effect_simulations_lemmas.
Require Import BuiltinEffects.

Require Export Axioms.
Require Import OpEFF.

Section PRESERVATION.

Variable prog: Mach.program.
Variable tprog: AsmEFF.program.
Hypothesis TRANSF: transf_program prog = Errors.OK tprog.

Variable hf : I64Helpers.helper_functions.
Let ge := Genv.globalenv prog.
Let tge := Genv.globalenv tprog.

Lemma symbols_preserved:
  forall id, Genv.find_symbol tge id = Genv.find_symbol ge id.
Proof.
  intros. unfold ge, tge. 
  apply Genv.find_symbol_transf_partial with transf_fundef.
  exact TRANSF. 
Qed.

Lemma functions_translated:
  forall b f,
  Genv.find_funct_ptr ge b = Some f ->
  exists tf, Genv.find_funct_ptr tge b = Some tf /\ transf_fundef f = Errors.OK tf.
Proof
  (Genv.find_funct_ptr_transf_partial transf_fundef _ TRANSF).

Lemma functions_transl:
  forall fb f tf,
  Genv.find_funct_ptr ge fb = Some (Internal f) ->
  transf_function f = OK tf ->
  Genv.find_funct_ptr tge fb = Some (Internal tf).
Proof.
  intros. exploit functions_translated; eauto. intros [tf' [A B]].
  monadInv B. rewrite H0 in EQ; inv EQ; auto. 
Qed.

Lemma varinfo_preserved:
  forall b, Genv.find_var_info tge b = Genv.find_var_info ge b.
Proof.
  intros. unfold ge, tge. 
  apply Genv.find_var_info_transf_partial with transf_fundef.
  exact TRANSF. 
Qed.

Lemma GDE_lemma: genvs_domain_eq ge tge.
Proof.
    unfold genvs_domain_eq, genv2blocks.
    simpl; split; intros.
     split; intros; destruct H as [id Hid].
      rewrite <- symbols_preserved in Hid.
      exists id; assumption.
     rewrite symbols_preserved in Hid.
      exists id; assumption.
     split; intros b. 
       split; intros; destruct H as [id Hid].
       rewrite <- varinfo_preserved in Hid.
       exists id; assumption.
       rewrite varinfo_preserved in Hid.
       exists id; assumption.
    intros. split.
      intros [f H].
        apply functions_translated in H. 
        destruct H as [? [? _]].
        eexists; eassumption.
     intros [f H].
         apply (@Genv.find_funct_ptr_rev_transf_partial
           _ _ _ transf_fundef prog _ TRANSF) in H.
         destruct H as [? [? _]]. eexists; eassumption.
Qed.
 
(** * Properties of control flow *)

Lemma transf_function_no_overflow:
  forall f tf,
  transf_function f = OK tf -> list_length_z (fn_code tf) <= Int.max_unsigned.
Proof.
  intros. monadInv H. destruct (zlt (list_length_z x) Int.max_unsigned); monadInv EQ0.
  simpl. rewrite list_length_z_cons. omega. 
Qed.

Lemma eff_exec_straight_exec:
  forall fb f c ep tf tc c' rs m rs' m' lf U,
  transl_code_at_pc ge (rs PC) fb f c ep tf tc ->
  eff_exec_straight tge tf U tc rs m c' rs' m' ->
  effstep_plus (Asm_eff_sem hf) tge U (State rs lf) m (State rs' lf) m'.
Proof.
  intros. inv H.
  eapply eff_exec_straight_steps_1; eauto.
  eapply transf_function_no_overflow; eauto.
  eapply functions_transl; eauto. 
Qed.

Lemma eff_exec_straight_at:
  forall fb f c ep tf tc c' ep' tc' rs m rs' m' U,
  transl_code_at_pc ge (rs PC) fb f c ep tf tc ->
  transl_code f c' ep' = OK tc' ->
  eff_exec_straight tge tf U tc rs m tc' rs' m' ->
  transl_code_at_pc ge (rs' PC) fb f c' ep' tf tc'.
Proof.
  intros. inv H. 
  exploit eff_exec_straight_steps_2; eauto. 
  eapply transf_function_no_overflow; eauto.
  eapply functions_transl; eauto.
  intros [ofs' [PC' CT']].
  rewrite PC'. constructor; auto.
Qed.

(** The following lemmas show that the translation from Mach to Asm
  preserves labels, in the sense that the following diagram commutes:
<<
                          translation
        Mach code ------------------------ Asm instr sequence
            |                                          |
            | Mach.find_label lbl       find_label lbl |
            |                                          |
            v                                          v
        Mach code tail ------------------- Asm instr seq tail
                          translation
>>
  The proof demands many boring lemmas showing that Asm constructor
  functions do not introduce new labels.

  In passing, we also prove a "is tail" property of the generated Asm code.
*)

Section TRANSL_LABEL.

Remark mk_mov_label:
  forall rd rs k c, mk_mov rd rs k = OK c -> tail_nolabel k c.
Proof.
  unfold mk_mov; intros. 
  destruct rd; try discriminate; destruct rs; TailNoLabel.
Qed.
Hint Resolve mk_mov_label: labels.

Remark mk_shrximm_label:
  forall n k c, mk_shrximm n k = OK c -> tail_nolabel k c.
Proof.
  intros. monadInv H; TailNoLabel.
Qed.
Hint Resolve mk_shrximm_label: labels.

Remark mk_intconv_label:
  forall f r1 r2 k c, mk_intconv f r1 r2 k = OK c -> 
  (forall r r', nolabel (f r r')) ->
  tail_nolabel k c.
Proof.
  unfold mk_intconv; intros. TailNoLabel. 
Qed.
Hint Resolve mk_intconv_label: labels.

Remark mk_smallstore_label:
  forall f addr r k c, mk_smallstore f addr r k = OK c -> 
  (forall r addr, nolabel (f r addr)) ->
  tail_nolabel k c.
Proof.
  unfold mk_smallstore; intros. TailNoLabel. 
Qed.
Hint Resolve mk_smallstore_label: labels.

Remark loadind_label:
  forall base ofs ty dst k c,
  loadind base ofs ty dst k = OK c ->
  tail_nolabel k c.
Proof.
  unfold loadind; intros. destruct ty.
  TailNoLabel.
  destruct (preg_of dst); TailNoLabel.
  discriminate.
  TailNoLabel.
Qed.

Remark storeind_label:
  forall base ofs ty src k c,
  storeind src base ofs ty k = OK c ->
  tail_nolabel k c.
Proof.
  unfold storeind; intros. destruct ty.
  TailNoLabel.
  destruct (preg_of src); TailNoLabel.
  discriminate.
  TailNoLabel.
Qed.

Remark mk_setcc_base_label:
  forall xc rd k,
  tail_nolabel k (mk_setcc_base xc rd k).
Proof.
  intros. destruct xc; simpl; destruct (ireg_eq rd EAX); TailNoLabel.
Qed.

Remark mk_setcc_label:
  forall xc rd k,
  tail_nolabel k (mk_setcc xc rd k).
Proof.
  intros. unfold mk_setcc. destruct (low_ireg rd).
  apply mk_setcc_base_label.
  eapply tail_nolabel_trans. apply mk_setcc_base_label. TailNoLabel.
Qed.

Remark mk_jcc_label:
  forall xc lbl' k,
  tail_nolabel k (mk_jcc xc lbl' k).
Proof.
  intros. destruct xc; simpl; TailNoLabel.
Qed.

Remark transl_cond_label:
  forall cond args k c,
  transl_cond cond args k = OK c ->
  tail_nolabel k c.
Proof.
  unfold transl_cond; intros.
  destruct cond; TailNoLabel.
  destruct (Int.eq_dec i Int.zero); TailNoLabel.
  destruct c0; simpl; TailNoLabel.
  destruct c0; simpl; TailNoLabel.
Qed.

Remark transl_op_label:
  forall op args r k c,
  transl_op op args r k = OK c ->
  tail_nolabel k c.
Proof.
  unfold transl_op; intros. destruct op; TailNoLabel.
  destruct (Int.eq_dec i Int.zero); TailNoLabel.
  destruct (Float.eq_dec f Float.zero); TailNoLabel.
  eapply tail_nolabel_trans. eapply transl_cond_label; eauto. eapply mk_setcc_label.  
Qed.

Remark transl_load_label:
  forall chunk addr args dest k c,
  transl_load chunk addr args dest k = OK c ->
  tail_nolabel k c.
Proof.
  intros. monadInv H. destruct chunk; TailNoLabel.
Qed.

Remark transl_store_label:
  forall chunk addr args src k c,
  transl_store chunk addr args src k = OK c ->
  tail_nolabel k c.
Proof.
  intros. monadInv H. destruct chunk; TailNoLabel.
Qed.

Lemma transl_instr_label:
  forall f i ep k c,
  transl_instr f i ep k = OK c ->
  match i with Mlabel lbl => c = Plabel lbl :: k | _ => tail_nolabel k c end.
Proof.
Opaque loadind.
  unfold transl_instr; intros; destruct i; TailNoLabel.
  eapply loadind_label; eauto.
  eapply storeind_label; eauto.
  eapply loadind_label; eauto.
  eapply tail_nolabel_trans; eapply loadind_label; eauto. 
  eapply transl_op_label; eauto.
  eapply transl_load_label; eauto.
  eapply transl_store_label; eauto.
  destruct s0; TailNoLabel.
  destruct s0; TailNoLabel.
  eapply tail_nolabel_trans. eapply transl_cond_label; eauto. eapply mk_jcc_label.  
Qed.

Lemma transl_instr_label':
  forall lbl f i ep k c,
  transl_instr f i ep k = OK c ->
  find_label lbl c = if Mach.is_label lbl i then Some k else find_label lbl k.
Proof.
  intros. exploit transl_instr_label; eauto.
  destruct i; try (intros [A B]; apply B). 
  intros. subst c. simpl. auto.
Qed.

Lemma transl_code_label:
  forall lbl f c ep tc,
  transl_code f c ep = OK tc ->
  match Mach.find_label lbl c with
  | None => find_label lbl tc = None
  | Some c' => exists tc', find_label lbl tc = Some tc' /\ transl_code f c' false = OK tc'
  end.
Proof.
  induction c; simpl; intros.
  inv H. auto.
  monadInv H. rewrite (transl_instr_label' lbl _ _ _ _ _ EQ0).
  generalize (Mach.is_label_correct lbl a). 
  destruct (Mach.is_label lbl a); intros.
  subst a. simpl in EQ. exists x; auto.
  eapply IHc; eauto.
Qed.

Lemma transl_find_label:
  forall lbl f tf,
  transf_function f = OK tf ->
  match Mach.find_label lbl f.(Mach.fn_code) with
  | None => find_label lbl (fn_code tf) = None
  | Some c => exists tc, find_label lbl (fn_code tf) = Some tc /\ transl_code f c false = OK tc
  end.
Proof.
  intros. monadInv H. destruct (zlt (list_length_z x) Int.max_unsigned); inv EQ0.
  simpl. eapply transl_code_label; eauto. rewrite transl_code'_transl_code in EQ; eauto. 
Qed.

End TRANSL_LABEL.

(** A valid branch in a piece of Mach code translates to a valid ``go to''
  transition in the generated PPC code. *)

Lemma find_label_goto_label:
  forall f tf lbl rs m c' b ofs,
  Genv.find_funct_ptr ge b = Some (Internal f) ->
  transf_function f = OK tf ->
  rs PC = Vptr b ofs ->
  Mach.find_label lbl f.(Mach.fn_code) = Some c' ->
  exists tc', exists rs',
    goto_label (fn_code tf) lbl rs m = Next rs' m  
  /\ transl_code_at_pc ge (rs' PC) b f c' false tf tc'
  /\ forall r, r <> PC -> rs'#r = rs#r.
Proof.
  intros. exploit (transl_find_label lbl f tf); eauto. rewrite H2. 
  intros [tc [A B]].
  exploit label_pos_code_tail; eauto. instantiate (1 := 0).
  intros [pos' [P [Q R]]].
  exists tc; exists (rs#PC <- (Vptr b (Int.repr pos'))).
  split. unfold goto_label. rewrite P. rewrite H1. auto.
  split. rewrite Pregmap.gss. constructor; auto. 
  rewrite Int.unsigned_repr. replace (pos' - 0) with pos' in Q.
  auto. omega.
  generalize (transf_function_no_overflow _ _ H0). omega.
  intros. apply Pregmap.gso; auto.
Qed.

(** Existence of return addresses *)

Lemma return_address_exists:
  forall f sg ros c, is_tail (Mcall sg ros :: c) f.(Mach.fn_code) ->
  exists ra, return_address_offset f c ra.
Proof.
  intros. eapply Asmgenproof0EFF.return_address_exists; eauto. 
- intros. exploit transl_instr_label; eauto. 
  destruct i; try (intros [A B]; apply A). intros. subst c0. repeat constructor.
- intros. monadInv H0. 
  destruct (zlt (list_length_z x) Int.max_unsigned); inv EQ0.
  rewrite transl_code'_transl_code in EQ.
  exists x; exists true; split; auto. unfold fn_code. repeat constructor.
- exact transf_function_no_overflow.
Qed.

(** * Proof of semantic preservation *)

(** Semantic preservation is proved using simulation diagrams
  of the following form.
<<
           st1 --------------- st2
            |                   |
           t|                  *|t
            |                   |
            v                   v
           st1'--------------- st2'
>>
  The invariant is the [match_states] predicate below, which includes:
- The PPC code pointed by the PC register is the translation of
  the current Mach code sequence.
- Mach register values and PPC register values agree.
*)

(*Definition sp_zero_or_local mu sp:= 
  sp=Vzero \/ exists spb ofs, sp=Vptr spb ofs /\ 
                              locBlocksSrc mu spb = true.
*)

Require Import load_frame.

Inductive match_load_frames mu: Mach_coop.load_frame -> mem -> Asm_coop.load_frame -> mem -> Prop :=
  | match_load_frames_intro: 
      forall sp0 tsp0 args tys retty m tm
        (SP: restrict (local_of mu) (vis mu) sp0 = Some (tsp0, 0)),
      match_load_frames mu (Mach_coop.mk_load_frame sp0 args tys retty) m
                           (Asm_coop.mk_load_frame tsp0 retty) tm.

Inductive match_states mu: Mach_core -> mem -> Asm_coop.state -> mem -> Prop :=
  | match_states_intro:
      forall s fb sp c ep ms m m' rs f tf tc sp0 tsp0 args tys retty
        (STACKS: match_stack ge (restrict_sm mu (vis mu)) s)
        (FIND: Genv.find_funct_ptr ge fb = Some (Internal f))
        (MEXT: Mem.inject (as_inj mu) m m')
        (AT: transl_code_at_pc ge (rs PC) fb f c ep tf tc)
        (AG: agree (restrict_sm mu (vis mu)) ms sp rs)
        (DXP: ep = true -> 
              val_inject (as_inj (restrict_sm mu (vis mu))) (parent_sp0 sp0 s) (rs#EDX))
        (SPlocal: sp_spec mu sp),
        let lf := Mach_coop.mk_load_frame sp0 args tys retty in
        let tlf := Asm_coop.mk_load_frame tsp0 retty in forall
        (MLF: match_load_frames mu lf m tlf m'),
      match_states mu (Mach_State s fb sp c ms lf) m (State rs tlf) m'

  | match_states_init:
      forall fb m0 m m' f args args' tys retty
        (FIND: Genv.find_funct_ptr ge fb = Some (Internal f))
        (MEXT: Mem.inject (as_inj mu) m m')
        (VINJ: val_list_inject (restrict (as_inj mu) (vis mu)) args args')
        (TYSEQ: sig_args (Mach.fn_sig f) = tys)
        (VALSDEF: val_casted.vals_defined args=true)
        (HASTY: Val.has_type_list args tys)
        (INITMEM: Genv.init_mem prog = Some m0)
        (Fwd: Ple (Mem.nextblock m0) (Mem.nextblock m))
        (Fwd': Ple (Mem.nextblock m0) (Mem.nextblock m'))
        (REP: 4*(2*Zlength args) < Int.max_unsigned),
      match_states mu (Mach_CallstateIn fb args tys retty) m
                      (Asm_CallstateIn fb args' tys retty) m'

(*NEW: distinguish internal and external calls*)
  | match_states_call_internal:
      forall s fb ms m m' rs sp0 tsp0 args tys retty
        (STACKS: match_stack ge (restrict_sm mu (vis mu)) s)
        (MEXT: Mem.inject (as_inj mu) m m')
        (AG: agree (restrict_sm mu (vis mu)) ms (parent_sp0 sp0 s) rs)
        (ATPC: rs PC = Vptr fb Int.zero)
        (ATLR: val_inject (as_inj (restrict_sm mu (vis mu))) (parent_ra s) (rs RA))
        f (INT: Genv.find_funct_ptr ge fb = Some (Internal f)),
        let lf := Mach_coop.mk_load_frame sp0 args tys retty in
        let tlf := Asm_coop.mk_load_frame tsp0 retty in forall
        (MLF: match_load_frames mu lf m tlf m'),
      match_states mu (Mach_Callstate s fb ms lf) m
                      (State rs tlf) m'

  | match_states_call_external:
      forall s fb ms m m' rs sp0 tsp0 args0 tys0 retty0
        (STACKS: match_stack ge (restrict_sm mu (vis mu)) s)
        (MEXT: Mem.inject (as_inj mu) m m')
        (AG: agree (restrict_sm mu (vis mu)) ms (parent_sp0 sp0 s) rs)
        (ATPC: rs PC = Vptr fb Int.zero)
        (ATLR: val_inject (as_inj (restrict_sm mu (vis mu))) (parent_ra s) (rs RA))
        ef (EF: Genv.find_funct_ptr ge fb = Some (External ef))
        args (ARGS: Mach.extcall_arguments ms m (parent_sp0 sp0 s) (ef_sig ef) args)
        args' (ARGS': extcall_arguments rs m' (ef_sig ef) args')
        (ArgsInj: val_list_inject (as_inj (restrict_sm mu (vis mu))) args args'),
        let lf := Mach_coop.mk_load_frame sp0 args0 tys0 retty0 in
        let tlf := Asm_coop.mk_load_frame tsp0 retty0 in forall
        (MLF: match_load_frames mu lf m tlf m'),
      match_states mu (Mach_CallstateOut s fb ef args ms lf) m
                      (Asm_CallstateOut ef args' rs tlf) m'

  | match_states_return:
      forall s ms m m' retty rs sp0 tsp0 args tys retty0
        (STACKS: match_stack ge (restrict_sm mu (vis mu)) s)
        (MEXT: Mem.inject (as_inj mu) m m')
        (AG: agree (restrict_sm mu (vis mu)) ms (parent_sp0 sp0 s) rs)
        (ATPC: val_inject (as_inj (restrict_sm mu (vis mu))) (parent_ra s) (rs PC)),
        let lf := Mach_coop.mk_load_frame sp0 args tys retty0 in
        let tlf := Asm_coop.mk_load_frame tsp0 retty0 in forall
        (MLF: match_load_frames mu lf m tlf m'),
      match_states mu (Mach_Returnstate s retty ms lf) m
                      (State rs tlf) m'.


Lemma eff_exec_straight_steps:
  forall mu s fb f rs1 i c ep tf tc m1' m2 m2' sp ms2 U sp0 tsp0 args tys retty,
  let lf := Mach_coop.mk_load_frame sp0 args tys retty in
  let tlf := Asm_coop.mk_load_frame tsp0 retty in 
  match_stack ge (restrict_sm mu (vis mu)) s ->
  Mem.inject (as_inj mu) m2 m2' -> (*Mem.extends m2 m2' ->*)
  Genv.find_funct_ptr ge fb = Some (Internal f) ->
  transl_code_at_pc ge (rs1 PC) fb f (i :: c) ep tf tc ->
  (forall k c (TR: transl_instr f i ep k = OK c),
   exists rs2,
       eff_exec_straight tge tf U c rs1 m1' k rs2 m2'
    /\ agree (restrict_sm mu (vis mu)) ms2 sp rs2
    /\ (it1_is_parent ep i = true ->
        val_inject (as_inj (restrict_sm mu (vis mu))) (parent_sp0 sp0 s) (rs2#EDX))) ->
  (*NEW*) forall 
  (SPlocal: sp_spec mu sp)
  (MLF: match_load_frames mu lf m2 tlf m2'),
  exists st',
  effstep_plus (Asm_eff_sem hf) tge U (State rs1 tlf) m1' st' m2' /\
  match_states mu (Mach_State s fb sp c ms2 lf) m2 st' m2'.
Proof.
  intros. inversion H2. subst. monadInv H7. 
  exploit H3; eauto. intros [rs2 [A [B C]]]. 
  exists (State rs2 tlf); split.
  eapply eff_exec_straight_exec; eauto. 
  econstructor; eauto. eapply eff_exec_straight_at; eauto.
Qed.

Lemma eff_exec_straight_steps_goto:
  forall mu s fb f rs1 i c ep tf tc m1' m2 m2' sp ms2 lbl c' sp0 tsp0 args tys retty,
  let lf := Mach_coop.mk_load_frame sp0 args tys retty in
  let tlf := Asm_coop.mk_load_frame tsp0 retty in 
  match_stack ge (restrict_sm mu (vis mu)) s ->
  Mem.inject (as_inj mu) m2 m2' -> 
  Genv.find_funct_ptr ge fb = Some (Internal f) ->
  Mach.find_label lbl f.(Mach.fn_code) = Some c' ->
  transl_code_at_pc ge (rs1 PC) fb f (i :: c) ep tf tc ->
  it1_is_parent ep i = false ->
  (forall k c (TR: transl_instr f i ep k = OK c),
   exists jmp, exists k', exists rs2,
       eff_exec_straight tge tf EmptyEffect c rs1 m1' (jmp :: k') rs2 m2'
    /\ agree (restrict_sm mu (vis mu)) ms2 sp rs2
    /\ exec_instr tge (fn_code tf) jmp rs2 m2' = goto_label (fn_code tf) lbl rs2 m2'
    /\ effect_instr tge (fn_code tf) jmp rs2 m2' = EmptyEffect) ->
  forall 
  (SPlocal: sp_spec mu sp)
  (MLF: match_load_frames mu lf m2 tlf m2'),
  exists st',
  effstep_plus (Asm_eff_sem hf) tge EmptyEffect (State rs1 tlf) m1' st' m2' /\
  match_states mu (Mach_State s fb sp c' ms2 lf) m2 st' m2'.
Proof.
  intros. inversion H3. subst. monadInv H9.
  exploit H5; eauto. intros [jmp [k' [rs2 [A [B [C D]]]]]].
  generalize (functions_transl _ _ _ H7 H8); intro FN.
  generalize (transf_function_no_overflow _ _ H8); intro NOOV.
  exploit eff_exec_straight_steps_2; eauto. 
  intros [ofs' [PC2 CT2]].
  exploit find_label_goto_label; eauto. 
  intros [tc' [rs3 [GOTO [AT' OTH]]]].
  exists (State rs3 tlf); split.
  eapply effstep_plus_trans'.
    eapply eff_exec_straight_steps_1; eauto.  
    eapply effstep_plus_one. 
      econstructor; eauto.
        eapply find_instr_tail. eauto. 
        rewrite C. eexact GOTO.
        rewrite D. intuition.
  econstructor; eauto.
  apply agree_exten with rs2; auto with asmgen.
     intros. apply OTH. intros N; subst; discriminate.
  congruence.
Qed.

Lemma restrict_sm_zero_or_localid mu X sp: forall
        (HX : forall b : block, vis mu b = true -> X b = true)
        (WD: SM_wd mu),
      sp_spec (restrict_sm mu X) sp =
      sp_spec mu sp.
Proof. unfold sp_spec; intros.
rewrite restrict_sm_local'; trivial.
Qed.

Lemma match_states_restrict mu c1 m1 c2 m2: forall
        (MS:match_states mu c1 m1 c2 m2) X
        (RC: REACH_closed m1 X)
        (HX : forall b : block, vis mu b = true -> X b = true)
        (WD: SM_wd mu),
      match_states (restrict_sm mu X) c1 m1 c2 m2.
Proof. intros. inv MS.
   econstructor; eauto.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     rewrite restrict_sm_all.
       eapply inject_restrict; try eassumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     rewrite restrict_sm_zero_or_localid; trivial.
     { inversion MLF. subst lf. subst. constructor; auto.
       rewrite vis_restrict_sm, restrict_sm_local, restrict_nest; auto. }
     unfold sp_spec.
   econstructor; eauto.
     rewrite restrict_sm_all.
       eapply inject_restrict; try eassumption.
     apply forall_inject_val_list_inject.
     apply restrict_forall_vals_inject.
     rewrite restrict_sm_all.
     apply restrict_forall_vals_inject.
     apply val_list_inject_forall_inject in VINJ.
     apply forall_vals_inject_restrictD' in VINJ.
     destruct VINJ; auto.
     apply val_list_inject_forall_inject in VINJ.
     apply forall_vals_inject_restrictD' in VINJ.
     destruct VINJ; auto.
     apply val_list_inject_forall_inject in VINJ.
     apply forall_vals_inject_restrictD' in VINJ.
     destruct VINJ. intros b0 Y. solve[rewrite vis_restrict_sm; auto].
     unfold sp_spec.
   econstructor; eauto.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
       rewrite restrict_sm_all.
       eapply inject_restrict; try eassumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.     
     { inversion MLF. subst lf. subst. constructor; auto.
       rewrite vis_restrict_sm, restrict_sm_local, restrict_nest; auto. }
   econstructor; eauto.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption. 
     rewrite restrict_sm_all.
       eapply inject_restrict; try eassumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption. 
     rewrite vis_restrict_sm, restrict_sm_nest; assumption. 
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     { inversion MLF. subst lf. subst. constructor; auto.
       rewrite vis_restrict_sm, restrict_sm_local, restrict_nest; auto. }
   econstructor; eauto.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption. 
     rewrite restrict_sm_all.
       eapply inject_restrict; try eassumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption.
     rewrite vis_restrict_sm, restrict_sm_nest; assumption. 
     { inversion MLF. subst lf. subst. constructor; auto.
       rewrite vis_restrict_sm, restrict_sm_local, restrict_nest; auto. }
Qed.

Definition MATCH (d:Mach_core) mu c1 m1 c2 m2:Prop :=
  match_states mu c1 m1 c2 m2 /\ 
  REACH_closed m1 (vis mu) /\
  meminj_preserves_globals ge (as_inj mu) /\
  globalfunction_ptr_inject ge (as_inj mu) /\
  (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true) /\
  sm_valid mu m1 m2 /\ SM_wd mu.

Lemma MATCH_wd: forall d mu c1 m1 c2 m2 
  (MC: MATCH d mu c1 m1 c2 m2), SM_wd mu.
Proof. intros. eapply MC. Qed.

Lemma MATCH_RC: forall d mu c1 m1 c2 m2 
  (MC: MATCH d mu c1 m1 c2 m2), REACH_closed m1 (vis mu).
Proof. intros. eapply MC. Qed.

Lemma MATCH_restrict: forall d mu c1 m1 c2 m2 X
  (MC: MATCH d mu c1 m1 c2 m2)
  (HX: forall b : block, vis mu b = true -> X b = true) 
  (RX: REACH_closed m1 X), 
  MATCH d (restrict_sm mu X) c1 m1 c2 m2.
Proof. intros.
  destruct MC as [MS [RC [PG [GF [Glob [SMV WD]]]]]].
assert (WDR: SM_wd (restrict_sm mu X)).
   apply restrict_sm_WD; assumption.
split.
  eapply match_states_restrict; eassumption.
split. unfold vis.
  rewrite restrict_sm_locBlocksSrc, restrict_sm_frgnBlocksSrc.
  apply RC.
split. clear -PG Glob HX.
  eapply restrict_sm_preserves_globals; try eassumption.
  unfold vis in HX. intuition.
split. rewrite restrict_sm_all. 
       eapply restrict_preserves_globalfun_ptr; try eassumption.
        intros. eapply HX. unfold vis. rewrite (Glob _ H). intuition.
split. 
  rewrite restrict_sm_frgnBlocksSrc. apply Glob.
split. 
  destruct SMV.
  split; intros.
    rewrite restrict_sm_DOM in H1.
    apply (H _ H1).
  rewrite restrict_sm_RNG in H1.
    apply (H0 _ H1).
assumption.
Qed.

Lemma MATCH_valid: forall d mu c1 m1 c2 m2 
  (MC: MATCH d mu c1 m1 c2 m2), sm_valid mu m1 m2.
Proof. intros. eapply MC. Qed.

Lemma MATCH_PG: forall d mu c1 m1 c2 m2 
  (MC: MATCH d mu c1 m1 c2 m2),
  meminj_preserves_globals ge (extern_of mu) /\
  (forall b : block, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true).
Proof.
  intros.
  assert (GF: forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true).
    apply MC.
  split; trivial.
  rewrite <- match_genv_meminj_preserves_extern_iff_all; trivial.
    apply MC. apply MC.
Qed.

Lemma agree_eval_addressing_inject: forall a mu rs args addr rs0 sp
      (EV: eval_addressing ge sp addr rs ## args = Some a)
      (PG : meminj_preserves_globals ge (as_inj mu))
      (Glob : forall b, isGlobalBlock ge b = true ->
              frgnBlocksSrc mu b = true)
      (WD : SM_wd mu)
      (AG : agree (restrict_sm mu (vis mu)) rs sp rs0)
      (SPlocal : sp_spec mu sp),
  exists a',
    eval_addressing ge (rs0 ESP) addr rs0 ## (preg_of ## args) = Some a' /\
    val_inject (as_inj (restrict_sm mu (vis mu))) a a'.
Proof. intros.
     destruct SPlocal.
     subst.
       eapply eval_addressing_sp_scalar; try eassumption.
         eapply sp_as_inj. eassumption.
            apply restrict_sm_WD; trivial. 
        eapply restrict_sm_preserves_globals with (X:=vis mu). eassumption.
          unfold vis; intuition.
        eapply preg_vals; eassumption.
Qed.

(** We need to show that, in the simulation diagram, we cannot
  take infinitely many Mach transitions that correspond to zero
  transitions on the PPC side.  Actually, all Mach transitions
  correspond to at least one Asm transition, except the
  transition from [Mach.Returnstate] to [Mach.State].
  So, the following integer measure will suffice to rule out
  the unwanted behaviour. *)

Definition measure (s: Mach_core) : nat :=
  match s with
  | Mach_Returnstate _ _ _ _ => 1%nat
  | _ => 0%nat
  end.

Lemma match_stack_intern_incr mu mu': forall
   (INC: intern_incr mu mu') s
   (MS: match_stack ge mu s),
   match_stack ge mu' s.
Proof. intros.
induction MS; econstructor; eauto.
eapply sp_spec_intern_incr; eassumption.
eapply ra_spec_intern_incr; eassumption.
Qed.

Section EXT_ARGUMENTS_LOADV.
Variable rs: regset.
Variable sg: signature.
Variable m1: mem.
Variable m2: mem.
Variable u: val.

(*NEW*)
Lemma extcall_argument_loadv:
  forall l (Hl: In l (loc_arguments sg))
  (HH: forall ofs ty, In (S Outgoing ofs ty) (loc_arguments sg) ->
          Mem.loadv (chunk_of_type ty) m2 (Val.add (rs ESP) 
                    (Vint (Int.repr (Stacklayout.fe_ofs_arg + 4 * ofs)))) =
          Mem.loadv (chunk_of_type ty) m1 (Val.add (rs ESP) 
                    (Vint (Int.repr (Stacklayout.fe_ofs_arg + 4 * ofs)))))
  v (EC: extcall_arg rs m1 l v),
  extcall_arg rs m2 l v. 
Proof.
  intros.
  assert (loc_argument_acceptable l). apply loc_arguments_acceptable with sg; auto.
  inv EC; econstructor.
  reflexivity. rewrite <- H1. apply HH. trivial.
Qed.

(*NEW*)
Lemma extcall_arguments_loadv:
  forall locs (Hlocs: incl locs (loc_arguments sg))
  (HH: forall ofs ty, In (S Outgoing ofs ty) (loc_arguments sg) ->
          Mem.loadv (chunk_of_type ty) m2 (Val.add (rs ESP) 
                    (Vint (Int.repr (Stacklayout.fe_ofs_arg + 4 * ofs)))) =
          Mem.loadv (chunk_of_type ty) m1 (Val.add (rs ESP) 
                    (Vint (Int.repr (Stacklayout.fe_ofs_arg + 4 * ofs)))))
  vl (VL: list_forall2 (extcall_arg rs m1) locs vl),
  list_forall2 (extcall_arg rs m2) locs vl.
Proof.
  induction locs; simpl; intros.
  inv VL. constructor. 
  inv VL. constructor.
    eapply extcall_argument_loadv.
      eapply Hlocs. left; trivial.
    assumption. assumption.
  eapply IHlocs; trivial.
    red; intros. eapply Hlocs. right; trivial.
Qed.
End EXT_ARGUMENTS_LOADV.

Lemma match_stack_replace_locals mu s PS PT: forall ge,
  match_stack ge mu s ->
  match_stack ge (replace_locals mu PS PT) s.
Proof.
intros.
induction H; try econstructor; eauto.
destruct H1 as [? [? [? [? ?]]]].
eexists; eexists; eexists. split; eauto. rewrite replace_locals_local; eauto.
destruct H2. left; auto.
right. rewrite replace_locals_local. assumption.
Qed.

Lemma MATCH_initial: forall v
  (vals1 : list val) c1 (m1 : mem) (j : meminj)
  (vals2 : list val) (m2 : mem) (DomS DomT : Values.block -> bool)
  (Ini :initial_core (Mach_eff_sem hf return_address_offset) ge v vals1 = Some c1)
  (Inj: Mem.inject j m1 m2)
  (VInj: Forall2 (val_inject j) vals1 vals2)
  (PG: meminj_preserves_globals ge j)
  (R : list_norepet (map fst (prog_defs prog)))
  (J: forall b1 b2 d, j b1 = Some (b2, d) -> 
                      DomS b1 = true /\ DomT b2 = true)
  (RCH: forall b, REACH m2
        (fun b' : Values.block => isGlobalBlock tge b' || getBlocks vals2 b') b =
         true -> DomT b = true)
  (InitMem : exists m0 : mem, Genv.init_mem prog = Some m0 
      /\ Ple (Mem.nextblock m0) (Mem.nextblock m1) 
      /\ Ple (Mem.nextblock m0) (Mem.nextblock m2))
  (GDE: genvs_domain_eq ge tge)
  (HDomS: forall b : Values.block, DomS b = true -> Mem.valid_block m1 b)
  (HDomT: forall b : Values.block, DomT b = true -> Mem.valid_block m2 b),
exists c2,
  initial_core (Asm_eff_sem hf)tge v vals2 = Some c2 /\
  MATCH c1
    (initial_SM DomS DomT
       (REACH m1
          (fun b : Values.block => isGlobalBlock ge b || getBlocks vals1 b))
       (REACH m2
          (fun b : Values.block => isGlobalBlock tge b || getBlocks vals2 b))
       j) c1 m1 c2 m2. 
Proof. intros.
  inversion Ini.
  unfold Mach_initial_core in H0. unfold ge in *. unfold tge in *.
  destruct v; inv H0.
  remember (Int.eq_dec i Int.zero) as z; destruct z; inv H1. clear Heqz.
  remember (Genv.find_funct_ptr (Genv.globalenv prog) b) as zz; destruct zz; inv H0. 
    apply eq_sym in Heqzz.
  destruct f; try discriminate.
  revert Ini. simpl. 
  case (Int.eq_dec Int.zero Int.zero). 
  2: solve[intros; elimtype False; auto].
  rewrite Heqzz.
  case_eq (val_casted.val_has_type_list_func vals1 (sig_args (Mach.funsig (Internal f))) &&
           val_casted.vals_defined vals1). 
  2: solve[intros Heq; rewrite Heq in H1; inv H1].
  intros Heq; rewrite Heq in H1; inv H1.

  simpl; revert H0; case_eq 
    (zlt (match match Zlength vals1 with 0%Z => 0%Z
                      | Z.pos y' => Z.pos y'~0 | Z.neg y' => Z.neg y'~0
                     end
               with 0%Z => 0%Z
                 | Z.pos y' => Z.pos y'~0~0 | Z.neg y' => Z.neg y'~0~0
               end) Int.max_unsigned).
  intros l _.
  2: simpl; solve[inversion 2].
  simpl. inversion 1. subst. intros _.

  exploit functions_translated; eauto. intros [tf [FP TF]].

  assert (Hlen: Zlength vals2 = Zlength vals1).
  { apply forall_inject_val_list_inject in VInj. clear - VInj. 
    induction VInj; auto. rewrite !Zlength_cons, IHVInj; auto. }

  assert (Hsig: Mach.fn_sig f=funsig tf).
  { unfold transf_fundef in TF.  simpl in TF. unfold bind in TF. 
    revert TF. case_eq (transf_function f); try solve[inversion 2].
    unfold transf_function. intros f0. unfold bind.
    destruct (transl_code' f (Mach.fn_code f) true); try solve[inversion 1].
    destruct (zlt (list_length_z c) Int.max_unsigned); try solve[inversion 1].
    inversion 1. inversion 1. simpl; auto. }

  exists (Asm_CallstateIn b vals2 (sig_args (funsig tf)) (sig_res (funsig tf))).
  split.

  subst. inv Heqzz. unfold tge in FP. inv FP. rewrite H2. inv Ini.
  unfold Asm_eff_sem, Asm_coop_sem. simpl.
  case_eq (Int.eq_dec Int.zero Int.zero). intros ? e.

  assert (val_casted.val_has_type_list_func vals2 (sig_args (funsig tf))=true) as ->.
  { eapply val_casted.val_list_inject_hastype; eauto.
    eapply forall_inject_val_list_inject; eauto.
    destruct (val_casted.vals_defined vals1); auto.
    rewrite andb_comm in Heq; simpl in Heq. solve[inv Heq].
    assert (sig_args (funsig tf) = sig_args (Mach.funsig (Internal f))) as ->.
    { simpl. rewrite Hsig. auto. }
    destruct (val_casted.val_has_type_list_func vals1
             (sig_args (Mach.funsig (Internal f)))); auto. }

  assert (val_casted.vals_defined vals2=true) as ->.
  { eapply val_casted.val_list_inject_defined.
    eapply forall_inject_val_list_inject; eauto.
    destruct (val_casted.vals_defined vals1); auto.
    rewrite andb_comm in Heq; inv Heq. }

  monadInv TF. rename x into tf. simpl in H0. inv H0.
  revert l. simpl. rewrite Hlen. case_eq 
      (zlt (match match Zlength vals1 with 0%Z => 0%Z
                      | Z.pos y' => Z.pos y'~0 | Z.neg y' => Z.neg y'~0
                     end
               with 0%Z => 0%Z
                 | Z.pos y' => Z.pos y'~0~0 | Z.neg y' => Z.neg y'~0~0
               end) Int.max_unsigned).
  simpl. solve[auto]. intros. elimtype False; omega. 
  intros CONTRA. solve[elimtype False; auto].

  destruct (core_initial_wd ge tge _ _ _ _ _ _ _  Inj
     VInj J RCH PG GDE HDomS HDomT _ (eq_refl _))
    as [AA [BB [CC [DD [EE [FF GG]]]]]].

  unfold MATCH.
  destruct InitMem as [m0 [X [Y Z]]].  
  intuition.

  rewrite Hsig. 
  apply match_states_init with (m0 := m0) (f := f); auto.
  solve[rewrite initial_SM_as_inj; auto].
  rewrite initial_SM_as_inj.
  apply forall_inject_val_list_inject.
  apply restrict_forall_vals_inject; auto.
  intros. unfold initial_SM, vis; simpl. apply REACH_nil. 
  solve[rewrite H, orb_comm; auto].
  solve[rewrite Hsig; auto].
  rewrite andb_true_iff in Heq. destruct Heq as [U W]. auto.
  rewrite andb_true_iff in Heq. destruct Heq as [U W]. 
  { revert U. simpl. rewrite Hsig. 
    solve[rewrite val_casted.val_has_type_list_func_charact; auto]. }
  rewrite initial_SM_as_inj; auto.
  red; intros. specialize (Genv.find_funct_ptr_not_fresh prog). intros.
  specialize (H1 _ _ _ X H). 
  destruct (valid_init_is_global _ R _ X _ H1) as [id Hid]. 
  destruct PG as [PGa [PGb PGc]]. split. 
  solve[rewrite initial_SM_as_inj; eapply PGa; eauto].
  unfold isGlobalBlock. 
  apply orb_true_iff. left. apply genv2blocksBool_char1.
  simpl. exists id; eassumption.
Qed.

Lemma MATCH_atExternal: forall mu c1 m1 c2 m2 e vals1 ef_sig
      (MTCH: MATCH c1 mu c1 m1 c2 m2)
      (AtExtSrc: at_external (Mach_eff_sem hf return_address_offset) c1 = 
                 Some (e, ef_sig, vals1)),
      Mem.inject (as_inj mu) m1 m2  /\
(exists vals2 : list val,
   Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2 /\
   at_external (Asm_eff_sem hf)c2 = Some (e, ef_sig, vals2) /\
   (forall pubSrc' pubTgt' : block -> bool,
    pubSrc' =
    (fun b : block => locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b) ->
    pubTgt' =
    (fun b : block => locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b) ->
    forall nu : SM_Injection,
    nu = replace_locals mu pubSrc' pubTgt' ->
    MATCH c1 nu c1 m1 c2 m2 /\ Mem.inject (shared_of nu) m1 m2)).
Proof. 
intros. 
destruct MTCH as [MS PRE].
destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
inv MS; simpl in AtExtSrc; inv AtExtSrc.
split; trivial. 
exists (decode_longs (sig_args (AST.ef_sig e)) args').
assert (H: 
   val_list_inject (restrict (as_inj mu) (vis mu))
     (decode_longs (sig_args (AST.ef_sig e)) args)
     (decode_longs (sig_args (AST.ef_sig e)) args')).
{ apply decode_longs_inject; auto.
  rewrite restrict_sm_all in ArgsInj. trivial. }
split.
revert H0. destruct (observableEF_dec hf ef); try solve[inversion 1]. 
inversion 1; subst.
solve[apply val_list_inject_forall_inject; auto]. 
exploit replace_locals_wd_AtExternal; try eassumption.
        apply val_list_inject_forall_inject in H.
        apply forall_vals_inject_restrictD in H. eassumption.
intros WDnu.
simpl. revert H0. destruct (observableEF_dec hf ef). 2: solve[inversion 1]. inversion 1; auto. 
intuition. subst. split. 
econstructor; try rewrite replace_locals_as_inj; try rewrite replace_locals_vis; eauto.
clear - STACKS WD MEXT WDnu. 
induction STACKS; econstructor; try eassumption.
            clear IHSTACKS. 
               destruct H1 as [b [ofs [tb [X Y]]]].
               exists b, ofs, tb. split; auto.
               rewrite restrict_sm_local' in Y.
               rewrite restrict_sm_local'.
               rewrite replace_locals_local. 
               assumption. auto.
              rewrite replace_locals_vis. auto. auto. auto.
            clear IHSTACKS. destruct H2.
              left. trivial.
              right. rewrite restrict_sm_local' in H2; trivial.
                     rewrite restrict_sm_local'; trivial.
                     rewrite replace_locals_local. assumption.
              rewrite replace_locals_vis. trivial.
          destruct AG; constructor.
            rewrite restrict_sm_local' in agree_sp_local; trivial.
                     rewrite restrict_sm_local'; trivial.
                     rewrite replace_locals_local. assumption.
                     rewrite replace_locals_vis. trivial.
            rewrite restrict_sm_all in agree_mregs.
                  rewrite restrict_sm_all. 
                  rewrite replace_locals_as_inj. assumption.
         rewrite restrict_sm_all, replace_locals_as_inj.
           rewrite restrict_sm_all in ATLR; trivial.
         rewrite restrict_sm_all, replace_locals_as_inj.
           rewrite restrict_sm_all in ArgsInj; trivial.
         { (*match_load_frames*)
           clear - MLF. inversion MLF. subst lf. subst. constructor; auto.
           rewrite replace_locals_local, replace_locals_vis; auto. }
rewrite replace_locals_as_inj, replace_locals_vis, replace_locals_frgnBlocksSrc.
intuition.
(*sm_valid*)
  red. rewrite replace_locals_DOM, replace_locals_RNG. apply SMV.
(*inject_shared*)
  eapply inject_shared_replace_locals; try eassumption.
  subst; trivial.
Qed.

Lemma MATCH_afterExternal: forall
      (GDE : genvs_domain_eq ge tge)
      mu st1 st2 m1 e vals1 m2 ef_sig vals2 e' ef_sig'
      (MemInjMu : Mem.inject (as_inj mu) m1 m2)
      (MatchMu: MATCH st1 mu st1 m1 st2 m2)
      (AtExtSrc : at_external (Mach_eff_sem hf return_address_offset) st1 = Some (e, ef_sig, vals1))
      (AtExtTgt : at_external (Asm_eff_sem hf)st2 = Some (e', ef_sig', vals2))
      (ValInjMu : Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2)
      (pubSrc' : block -> bool)
      (pubSrcHyp : pubSrc' =
                 (fun b : block => 
                 locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b))
      (pubTgt' : block -> bool)
      (pubTgtHyp: pubTgt' =
                 (fun b : block => 
                 locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b))
       nu (NuHyp: nu = replace_locals mu pubSrc' pubTgt')
       nu' ret1 m1' ret2 m2' 
       (INC: extern_incr nu nu')
       (SEP: sm_inject_separated nu nu' m1 m2)
       (WDnu': SM_wd nu')
       (SMvalNu': sm_valid nu' m1' m2')
       (MemInjNu': Mem.inject (as_inj nu') m1' m2')
       (RValInjNu': val_inject (as_inj nu') ret1 ret2)
       (FwdSrc: mem_forward m1 m1')
       (FwdTgt: mem_forward m2 m2')
       (frgnSrc' : block -> bool)
       (frgnSrcHyp: frgnSrc' =
             (fun b : block => DomSrc nu' b &&
            (negb (locBlocksSrc nu' b) && REACH m1' (exportedSrc nu' (ret1 :: nil)) b)))
       (frgnTgt' : block -> bool)
       (frgnTgtHyp: frgnTgt' =
            (fun b : block => DomTgt nu' b &&
             (negb (locBlocksTgt nu' b) && REACH m2' (exportedTgt nu' (ret2 :: nil)) b)))
       mu' (Mu'Hyp: mu' = replace_externs nu' frgnSrc' frgnTgt')
       (UnchPrivSrc: Mem.unchanged_on
               (fun b z => locBlocksSrc nu b = true /\ pubBlocksSrc nu b = false) m1 m1')
       (UnchLOOR: Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'),
  exists st1' st2',
  after_external (Mach_eff_sem hf return_address_offset) (Some ret1) st1 =Some st1' /\
  after_external (Asm_eff_sem hf)(Some ret2) st2 = Some st2' /\
  MATCH st1' mu' st1' m1' st2' m2'.
Proof. intros.
destruct MatchMu as [MS PRE].
destruct PRE as [RC [PG [GFP [Glob [SMV WDmu]]]]].
simpl in *. inv MS; simpl in *; inv AtExtSrc.
 inv AtExtTgt.
 eexists. eexists.
    split. reflexivity.
    split. reflexivity.
 simpl in *.
 assert (INCvisNu': inject_incr
  (restrict (as_inj nu')
     (vis
        (replace_externs nu'
           (fun b : Values.block =>
            DomSrc nu' b &&
            (negb (locBlocksSrc nu' b) &&
             REACH m1' (exportedSrc nu' (ret1 :: nil)) b))
           (fun b : Values.block =>
            DomTgt nu' b &&
            (negb (locBlocksTgt nu' b) &&
             REACH m2' (exportedTgt nu' (ret2 :: nil)) b))))) (as_inj nu')).
      unfold vis. rewrite replace_externs_frgnBlocksSrc, replace_externs_locBlocksSrc.
      apply restrict_incr. 
assert (RC': REACH_closed m1' (mapped (as_inj nu'))).
        eapply inject_REACH_closed; eassumption.
assert (PGnu': meminj_preserves_globals (Genv.globalenv prog) (as_inj nu')).
    subst. clear - INC SEP PG GFP Glob WDmu WDnu'.
    apply meminj_preserves_genv2blocks in PG.
    destruct PG as [PGa [PGb PGc]].
    apply meminj_preserves_genv2blocks.
    split; intros.
      specialize (PGa _ H).
      apply joinI; left. apply INC.
      rewrite replace_locals_extern.
      assert (GG: isGlobalBlock ge b = true).
          unfold isGlobalBlock, ge. apply genv2blocksBool_char1 in H.
          rewrite H. trivial.
      destruct (frgnSrc _ WDmu _ (Glob _ GG)) as [bb2 [dd [FF FT2]]].
      rewrite (foreign_in_all _ _ _ _ FF) in PGa. inv PGa.
      apply foreign_in_extern; eassumption.
    split; intros. specialize (PGb _ H).
      apply joinI; left. apply INC.
      rewrite replace_locals_extern.
      assert (GG: isGlobalBlock ge b = true).
          unfold isGlobalBlock, ge. apply genv2blocksBool_char2 in H.
          rewrite H. intuition.
      destruct (frgnSrc _ WDmu _ (Glob _ GG)) as [bb2 [dd [FF FT2]]].
      rewrite (foreign_in_all _ _ _ _ FF) in PGb. inv PGb.
      apply foreign_in_extern; eassumption.
    eapply (PGc _ _ delta H). specialize (PGb _ H). clear PGa PGc.
      remember (as_inj mu b1) as d.
      destruct d; apply eq_sym in Heqd.
        destruct p. 
        apply extern_incr_as_inj in INC; trivial.
        rewrite replace_locals_as_inj in INC.
        rewrite (INC _ _ _ Heqd) in H0. trivial.
      destruct SEP as [SEPa _].
        rewrite replace_locals_as_inj, replace_locals_DomSrc, replace_locals_DomTgt in SEPa. 
        destruct (SEPa _ _ _ Heqd H0).
        destruct (as_inj_DomRng _ _ _ _ PGb WDmu).
        congruence.
assert (RR1: REACH_closed m1'
  (fun b : Values.block =>
   locBlocksSrc nu' b
   || DomSrc nu' b &&
      (negb (locBlocksSrc nu' b) &&
       REACH m1' (exportedSrc nu' (ret1 :: nil)) b))).
  intros b Hb. rewrite REACHAX in Hb. destruct Hb as [L HL].
  generalize dependent b.
  induction L; simpl; intros; inv HL.
     assumption.
  specialize (IHL _ H3); clear H3.
  apply orb_true_iff in IHL.
  remember (locBlocksSrc nu' b') as l.
  destruct l; apply eq_sym in Heql.
  (*case locBlocksSrc nu' b' = true*)
  { clear IHL.
    remember (pubBlocksSrc nu' b') as p.
    destruct p; apply eq_sym in Heqp.
      assert (Rb': REACH m1' (mapped (as_inj nu')) b' = true).
        apply REACH_nil. 
        destruct (pubSrc _ WDnu' _ Heqp) as [bb2 [dd1 [PUB PT]]].
        eapply mappedI_true.
         apply (pub_in_all _ WDnu' _ _ _ PUB).
      assert (Rb:  REACH m1' (mapped (as_inj nu')) b = true).
        eapply REACH_cons; try eassumption.
      specialize (RC' _ Rb).
      destruct (mappedD_true _ _ RC') as [[b2 d1] AI'].
      remember (locBlocksSrc nu' b) as d.
      destruct d; simpl; trivial.
      apply andb_true_iff. 
      split. eapply as_inj_DomRng; try eassumption.
      eapply REACH_cons; try eassumption.
        apply REACH_nil. unfold exportedSrc.
        rewrite (pubSrc_shared _ WDnu' _ Heqp). intuition.
      destruct (UnchPrivSrc) as [UP UV]; clear UnchLOOR.
        specialize (UP b' z Cur Readable). 
        specialize (UV b' z). 
        destruct INC as [_ [_ [_ [_ [LCnu' [_ [PBnu' [_ [FRGnu' _]]]]]]]]].
        rewrite <- LCnu'. rewrite replace_locals_locBlocksSrc.  
        rewrite <- LCnu' in Heql. rewrite replace_locals_locBlocksSrc in *.
        rewrite <- PBnu' in Heqp. rewrite replace_locals_pubBlocksSrc in *.
        clear INCvisNu'. 
        rewrite Heql in *. simpl in *. intuition.
        assert (VB: Mem.valid_block m1 b').
          eapply SMV. unfold DOM, DomSrc. rewrite Heql. intuition.
        apply (H VB) in H4.
        rewrite (H2 H4) in H6. clear H2 H.
        remember (locBlocksSrc mu b) as q.
        destruct q; simpl; trivial; apply eq_sym in Heqq.
        assert (Rb : REACH m1 (vis mu) b = true).
           eapply REACH_cons; try eassumption.
           apply REACH_nil. unfold vis. rewrite Heql; trivial.
        specialize (RC _ Rb). unfold vis in RC.
           rewrite Heqq in RC; simpl in *.
        rewrite replace_locals_frgnBlocksSrc in FRGnu'.
        rewrite FRGnu' in RC.
        apply andb_true_iff.  
        split. unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ RC). intuition.
        apply REACH_nil. unfold exportedSrc.
          rewrite (frgnSrc_shared _ WDnu' _ RC). intuition. }
  (*case DomSrc nu' b' &&
    (negb (locBlocksSrc nu' b') &&
     REACH m1' (exportedSrc nu' (ret1 :: nil)) b') = true*)
  { destruct IHL. congruence.
    apply andb_true_iff in H. simpl in H. 
    destruct H as [DomNu' Rb']. 
    clear INC SEP INCvisNu' UnchLOOR UnchPrivSrc.
    remember (locBlocksSrc nu' b) as d.
    destruct d; simpl; trivial. apply eq_sym in Heqd.
    apply andb_true_iff.
    split. assert (RET: Forall2 (val_inject (as_inj nu')) (ret1::nil) (ret2::nil)).
              constructor. assumption. constructor.
           destruct (REACH_as_inj _ WDnu' _ _ _ _ MemInjNu' RET
               _ Rb' (fun b => true)) as [b2 [d1 [AI' _]]]; trivial.
           assert (REACH m1' (mapped (as_inj nu')) b = true).
             eapply REACH_cons; try eassumption.
             apply REACH_nil. eapply mappedI_true; eassumption.
           specialize (RC' _ H). 
           destruct (mappedD_true _ _ RC') as [[? ?] ?].
           eapply as_inj_DomRng; eassumption.
    eapply REACH_cons; try eassumption. }
    
assert (RRC: REACH_closed m1' (fun b : Values.block =>
                         mapped (as_inj nu') b &&
                           (locBlocksSrc nu' b
                            || DomSrc nu' b &&
                               (negb (locBlocksSrc nu' b) &&
                           REACH m1' (exportedSrc nu' (ret1 :: nil)) b)))).
{ eapply REACH_closed_intersection; eassumption. }
assert (GFnu': forall b, isGlobalBlock (Genv.globalenv prog) b = true ->
               DomSrc nu' b &&
               (negb (locBlocksSrc nu' b) && REACH m1' (exportedSrc nu' (ret1 :: nil)) b) = true).
{ intros. specialize (Glob _ H).
  assert (FSRC:= extern_incr_frgnBlocksSrc _ _ INC).
  { rewrite replace_locals_frgnBlocksSrc in FSRC. 
    rewrite FSRC in Glob.
    rewrite (frgnBlocksSrc_locBlocksSrc _ WDnu' _ Glob). 
    apply andb_true_iff; simpl.
    split.
    unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ Glob). intuition.
    apply REACH_nil. unfold exportedSrc.
    rewrite (frgnSrc_shared _ WDnu' _ Glob). intuition. }}
assert (LL: local_of mu = local_of nu').
{ destruct INC. rewrite replace_locals_local in H2. eapply H2. }
assert (WDnuRE: SM_wd
  (replace_externs nu'
     (fun b : block =>
      DomSrc nu' b &&
      (negb (locBlocksSrc nu' b) &&
       REACH m1' (exportedSrc nu' (ret1 :: nil)) b))
     (fun b : block =>
      DomTgt nu' b &&
      (negb (locBlocksTgt nu' b) &&
       REACH m2' (exportedTgt nu' (ret2 :: nil)) b)))).
{ eapply replace_externs_wd. assumption.
  clear - WDnu'  RValInjNu' MemInjNu'. intros.  
  apply andb_true_iff in H; destruct H.
  apply andb_true_iff in H0; destruct H0.
  remember (locBlocksSrc nu' b1) as d.
  apply eq_sym in Heqd. destruct d; inv H0.
  exploit (REACH_extern_REACH nu'); try eassumption.
  econstructor. eassumption. econstructor.
  intros [b2 [delta [EXT REXT]]].
  exists b2, delta. split; trivial.
  destruct (extern_DomRng _ WDnu' _ _ _ EXT). 
  unfold DomTgt. rewrite H2, REXT.
  rewrite (extBlocksTgt_locBlocksTgt _ WDnu' _ H2).
  trivial.
  intros. apply andb_true_iff in H; destruct H.
  apply andb_true_iff in H2; destruct H2.
  unfold DomTgt in H.
  destruct (locBlocksTgt nu' b). inv H2. simpl in H; trivial. }

assert (II: inject_incr (as_inj (restrict_sm mu (vis mu)))
  (restrict (as_inj nu')
     (fun b : block =>
      locBlocksSrc nu' b
      || DomSrc nu' b &&
         (negb (locBlocksSrc nu' b) &&
          REACH m1' (exportedSrc nu' (ret1 :: nil)) b)))).
{ clear - INC WDnu'.
  specialize (extern_incr_restrict _ _ INC WDnu').
  rewrite replace_locals_as_inj, replace_locals_vis.
  red; intros; clear INC. rewrite restrict_sm_all in H0. 
  apply H in H0. destruct (restrictD_Some _ _ _ _ _ H0).
  apply restrictI_Some; trivial.
  destruct (as_inj_DomRng _ _ _ _ H1 WDnu'). rewrite H3.
  unfold DomSrc in H3; simpl.
  unfold vis in H2. destruct (locBlocksSrc nu' b); simpl in *; trivial.
  apply REACH_nil. unfold exportedSrc.
  apply frgnSrc_shared in H2; trivial.
  solve[rewrite H2; intuition]. }

assert (II': inject_incr (local_of (restrict_sm mu (vis mu)))
  (restrict (local_of nu')
     (fun b : block =>
      locBlocksSrc nu' b
      || DomSrc nu' b &&
         (negb (locBlocksSrc nu' b) &&
          REACH m1' (exportedSrc nu' (ret1 :: nil)) b)))).
{ clear - INC WDnu' WDmu.
  destruct INC as [_ [EQ [_ [_ [EQ1 [_ [_ [_ [EQ2 _]]]]]]]]].
  rewrite replace_locals_local in EQ. 
  rewrite replace_locals_locBlocksSrc in EQ1.
  rewrite replace_locals_frgnBlocksSrc in EQ2.
  rewrite restrict_sm_local. intros b b' d H.
  destruct (restrictD_Some _ _ _ _ _ H).
  apply restrictI_Some.
  solve[rewrite <-EQ; auto].
  unfold vis in H1. rewrite orb_true_iff in H1. rewrite <-EQ1.
  rewrite orb_true_iff.
  destruct H1. solve[left; auto]. right.
  rewrite andb_true_iff. split.
  unfold DomSrc. rewrite orb_true_iff. 
  rewrite EQ2 in H1. right. 
  solve[eapply frgnBlocksSrc_extBlocksSrc; eauto].
  rewrite andb_true_iff. split. 
  apply frgnBlocksSrc_locBlocksSrc in H1; auto. 
  solve[rewrite H1; auto].
  apply REACH_nil. unfold exportedSrc.
  rewrite EQ2 in H1.
  apply frgnSrc_shared in H1; trivial.
  solve[rewrite H1; intuition]. }
  
split.
{ econstructor. 
       rewrite replace_externs_vis. 
       clear - LL II WDnuRE STACKS WDmu WDnu' RValInjNu' MemInjNu'.
       induction STACKS; econstructor; eauto.
       clear IHSTACKS STACKS H2 H H0. 
         destruct H1 as [b [ofs [tb [X Y]]]]. 
         exists b, ofs, tb. split; auto.
           rewrite restrict_sm_local' in Y; trivial. 
           rewrite restrict_sm_local'; trivial. 
           rewrite replace_externs_local; trivial.
           rewrite <- LL. trivial. 
           rewrite replace_externs_vis. solve[trivial].
       clear IHSTACKS STACKS H1 H H0. 
         destruct H2. 
         left; trivial. 
         right.  rewrite restrict_sm_local'; trivial. 
                rewrite restrict_sm_local' in H; trivial. 
                rewrite replace_externs_local; trivial.
                rewrite <- LL. trivial. 
            rewrite replace_externs_vis. trivial.
rewrite replace_externs_as_inj. trivial.
rewrite replace_externs_vis. unfold loc_external_result.
  apply agree_set_other; trivial. 
  eapply agree_set_mregs.
  Focus 2. rewrite restrict_sm_all, replace_externs_as_inj.
           clear - WDnu' RValInjNu'. apply encode_long_inject.
           inv RValInjNu'; try econstructor; eauto.
           eapply restrictI_Some; trivial.
           destruct (as_inj_DomRng _ _ _ _ H WDnu'). rewrite H0.
           destruct (locBlocksSrc nu' b1); simpl. trivial.
           apply REACH_nil. unfold exportedSrc.
             apply orb_true_iff; left.
             rewrite getBlocks_char. eexists; left. reflexivity.
  clear - LL II AG INC WDmu WDnu' WDnuRE. destruct AG.
  constructor; intros.
    rewrite restrict_sm_local'; trivial.
    rewrite restrict_sm_local' in agree_sp_local; trivial.
    rewrite replace_externs_local. rewrite <- LL; trivial.
    rewrite replace_externs_vis. trivial.
  rewrite restrict_sm_all. rewrite replace_externs_as_inj. 
    eapply val_inject_incr.
    Focus 2. eapply agree_mregs. assumption.
  rewrite restrict_sm_all, replace_externs_as_inj, replace_externs_vis.
    rewrite Pregmap.gss. eapply val_inject_incr; try eassumption. 
(*match_load_frames*)
inversion MLF. subst lf. subst. constructor; auto. 
rewrite replace_externs_local.
rewrite replace_externs_vis.
apply II'.
inv SP.
rewrite restrict_sm_local; auto.
}

unfold vis in *.
rewrite replace_externs_locBlocksSrc, replace_externs_frgnBlocksSrc,
        replace_externs_as_inj in *.
destruct (eff_after_check2 _ _ _ _ _ MemInjNu' RValInjNu' 
      _ (eq_refl _) _ (eq_refl _) _ (eq_refl _) WDnu' SMvalNu').
unfold vis in *.
intuition.
(*last goal: globalfunction_ptr_inject *)
  red; intros. destruct (GFP _ _ H3). split; trivial.
  eapply extern_incr_as_inj; try eassumption.
  rewrite replace_locals_as_inj. assumption.
Qed.

Lemma MATCH_effcore_diagram: forall st1 m1 st1' m1' (U1 : block -> Z -> bool)
      (CS: effstep (Mach_eff_sem hf return_address_offset) ge U1 st1 m1 st1' m1')
      st2 mu m2
      (MTCH: MATCH st1 mu st1 m1 st2 m2),
exists st2' m2' (U2 : block -> Z -> bool),
     (effstep_plus (Asm_eff_sem hf)tge U2 st2 m2 st2' m2' \/
      (measure st1' < measure st1)%nat /\
      effstep_star (Asm_eff_sem hf)tge U2 st2 m2 st2' m2')
 /\ exists mu',
    intern_incr mu mu' /\
    sm_inject_separated mu mu' m1 m2 /\
    sm_locally_allocated mu mu' m1 m2 m1' m2' /\
    MATCH st1' mu' st1' m1' st2' m2' /\
   (forall 
      (U1Vis: forall b ofs, U1 b ofs = true -> vis mu b = true)
      b ofs, U2 b ofs = true ->
      visTgt mu b = true /\
      (locBlocksTgt mu b = false ->
       exists (b1 : block) (delta1 : Z),
         foreign_of mu b1 = Some (b, delta1) /\
         U1 b1 (ofs - delta1) = true /\
         Mem.perm m1 b1 (ofs - delta1) Max Nonempty)).
Proof. intros.
destruct CS; intros; destruct MTCH as [MS PRE]; try inv MS.

{ (* Mlabel *)
  exploit eff_exec_straight_steps; try eassumption.
  intros. monadInv TR. econstructor; split. apply eff_exec_straight_one. 
    simpl; eauto. auto. 
    reflexivity.
    split. apply agree_nextinstr; auto. eassumption. simpl; congruence.
  intros [st' [CS' MS']].
  eexists; exists m2. 
  eexists; split. left; eassumption. 
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  simpl; intros. intuition.  }

{ (* Mgetstack *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  unfold load_stack in H. 
  assert (SPptr: exists spb z, sp = Vptr spb z).
     destruct sp; inv H. exists b, i; trivial.
  destruct SPptr as [spb [z SP]]; subst; simpl in H. 
  destruct (sp_spec_ptr _ _ _ SPlocal) as [tb locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H3; trivial. 
  rewrite locSP in H3; apply eq_sym in H3; inv H3.
  rename H2 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu))));
    try eassumption.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    (*rewrite restrict_sm_local in locSP.
      destruct (restrictD_Some _ _ _ _ _ locSP).*)
      apply local_in_all in locSP; trivial.
      rewrite restrict_sm_all.
      eapply restrictI_Some; eassumption.
  rewrite Zplus_0_r.
  intros [v' [A B]].
  exploit (eff_exec_straight_steps mu); try eassumption. 
    intros. simpl in TR.
    exploit loadind_correct_eff. eassumption. 
       instantiate (2:=rs0). rewrite <- RSP; simpl. eassumption.
  intros [rs' [P [Q R]]].
  exists rs'; split. eauto.
  split. 
    eapply agree_set_mreg. eassumption.
    instantiate (1:=dst). instantiate (1:=v). rewrite Q. assumption.
    assumption.
    simpl. congruence.
  intros [st' [CS' MS']].
  exists st', m2. 
  eexists; split. left; eassumption. 
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  intuition. }

{ (* Msetstack *)
  unfold store_stack in H.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (SPptr: exists spb z, sp = Vptr spb z).
     destruct sp; inv H. exists b, i; trivial.
  destruct SPptr as [spb [z SP]]; subst; simpl in H.
  destruct (sp_spec_ptr _ _ _ SPlocal) as [tb locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H3; trivial. 
  rewrite locSP in H3; apply eq_sym in H3; inv H3.
  rename H2 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  exploit (Mem.store_mapped_inject (as_inj mu));
    try eassumption.
      apply local_in_all in locSP; trivial.
      eassumption.
    eapply val_inject_incr; try eapply AG. 
        rewrite restrict_sm_all. apply restrict_incr. 
  simpl. rewrite Zplus_0_r. intros [m2' [A B]].
  exploit (eff_exec_straight_steps mu). eassumption. apply B. eassumption. eassumption.
    intros. simpl in TR.
    exploit storeind_correct_eff. eassumption. 
     instantiate (2:=rs0). rewrite <- RSP. simpl. apply A.
  intros [rs' [P Q]].
  eexists; split. eassumption.
    split. eapply agree_undef_regs; eauto. 
    simpl; intros. rewrite Q; auto with asmgen. 
Local Transparent destroyed_by_setstack.
  destruct ty; simpl; intuition congruence.
  assumption. 
  inv MLF. solve[constructor; eauto].
  intros [st' [CS' MS']].
  assert (SMV': sm_valid mu m' m2').
    split; intros. 
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
  exists st', m2'.
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (store_freshloc _ _ _ _ _ _ H). intuition.
      apply extensionality; intros; rewrite (store_freshloc _ _ _ _ _ _ A). intuition. 
      apply extensionality; intros; rewrite (store_freshloc _ _ _ _ _ _ H). intuition.
      apply extensionality; intros; rewrite (store_freshloc _ _ _ _ _ _ A). intuition. 
  split. split; intuition. eauto.
         eapply REACH_Store; try eassumption.
          intros b' Hb'. rewrite getBlocks_char in Hb'. destruct Hb' as [off Hoff].
                  destruct Hoff; try contradiction.
                  specialize (agree_mregs _ _ _ _ AG src); intros AMR.
                   rewrite H0 in AMR; inv AMR.   
                   rewrite restrict_sm_all in H4. 
                   destruct (restrictD_Some _ _ _ _ _ H4); trivial. 
  simpl; intros. 
    apply StoreEffectD in H0. rewrite <- RSP in H0; simpl in H0.
    destruct H0 as [i [PtrEq Arith]]; inv PtrEq.
    destruct (local_DomRng _ WD _ _ _ locSP) as [DS DT].
    unfold visTgt. rewrite DT. intuition. }

{ (* Mgetparam *)
  inversion MS. subst tys0. subst args0. unfold lf0,lf1,lf2 in *. subst sp0. subst.
  assert (f0 = f) by congruence; subst f0.
  unfold load_stack in *. 
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (SPptr: exists spb z, sp = Vptr spb z).
  { destruct sp; inv H0. exists b, i; trivial. }
  destruct SPptr as [spb [z SP]]; subst; simpl in H0.
  destruct (sp_spec_ptr _ _ _ SPlocal) as [tb locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H5; trivial. 
  rewrite locSP in H5; apply eq_sym in H5; inv H5.
  rename H4 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
  { rewrite restrict_sm_all. eapply inject_restrict; eassumption. }
  { eexact H0. }
  { apply local_in_all in locSP; trivial.
      rewrite restrict_sm_all. eapply restrictI_Some; eassumption. }
  rewrite Zplus_0_r.
  intros [parent' [A B]]. simpl in *.
  remember (parent_sp0 sp2 s) as u. destruct u; simpl in *; try inv H1.
  inv B.
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    { unfold Mem.loadv in H3. revert H3.
      case_eq (Val.add (parent_sp0 sp2 s) (Vint ofs)); 
        try solve[intros; congruence|eauto]. }
    eauto.
  intros [v' [C D]].
Opaque loadind.
  exploit (eff_exec_straight_steps mu); eauto.
    intros. instantiate (2:=m2). (*instantiate (1 := (Vptr spb z)).*)
      instantiate(1 := (@Regmap.set val dst v
                      (@Regmap.set val temp_for_parent_frame Vundef rs))).
    assert (DIFF: negb (mreg_eq dst DX) = true -> IR EDX <> preg_of dst).
    { intros. change (IR EDX) with (preg_of DX). red; intros. 
      unfold proj_sumbool in H1. destruct (mreg_eq dst DX); try discriminate.
      elim n. solve[eapply preg_of_injective; eauto]. }
    assert (Int.unsigned (Int.add (Int.add i (Int.repr delta)) ofs)
              = Int.unsigned (Int.add i ofs) + delta).
    { rewrite Int.add_assoc. rewrite (Int.add_commut (Int.repr delta)).
      rewrite <- Int.add_assoc. 
      eapply Mem.address_inject; try eassumption. 
      eapply Mem.load_valid_access. eapply H3.
        split. omega. specialize (size_chunk_pos (chunk_of_type ty)); intros. omega.
      rewrite restrict_sm_all in H4. eapply restrictD_Some. eassumption. }
    rewrite <- H1 in C. clear H1.
    destruct ep; simpl in TR.
    (* EDX contains parent *)
      assert (VI: val_inject (as_inj (restrict_sm mu (vis mu))) (Vptr b i) (rs0 EDX)) 
        by eauto.
      clear DXP. inv VI. rewrite H4 in H6. inv H6.
      exploit loadind_correct_eff. eexact TR. 
        instantiate (2 := rs0). rewrite <- H5. simpl. apply C. 
      intros [rs1 [P [Q R]]].
      exists rs1; split. eauto. 
      split. eapply agree_set_mreg. eapply agree_set_mreg; eauto. congruence. auto.
      simpl; intros. rewrite R, <- Hequ, <- H5. econstructor. eassumption. trivial.
      auto. auto.
    (* EDX does not contain parent *)
      monadInv TR.
      exploit loadind_correct_eff. eexact EQ0.
      instantiate (2:=rs0). rewrite <- RSP. simpl. eauto.
      intros [rs1 [P [Q R]]]. simpl in Q.
      exploit loadind_correct_eff. eexact EQ.
        instantiate (2 := rs1). rewrite Q. simpl. eauto.
      intros [rs2 [S [T U]]]. 
      exists rs2; split. eapply eff_exec_straight_trans; eauto.
      split. eapply agree_set_mreg. eapply agree_set_mreg; eauto. congruence. auto.
      simpl; intros. rewrite U, <- Hequ, Q. econstructor. eassumption. trivial. 
      auto. auto.

  intros [st' [CS' MS']].
  exists st', m2.
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  intuition. }

{ (* Mop *)
  assert (eval_operation tge sp op rs##args m = Some v). 
    rewrite <- H. apply eval_operation_preserved. exact symbols_preserved.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  specialize (agree_sp_local _ _ _ _ AG); intros LocSP.
  exploit (preg_vals (restrict_sm mu (vis mu))). eassumption.
  intros ArgsInj.
  exploit eval_operation_inject''; try eapply H0; try eapply ArgsInj.
    eapply val_inject_incr; try eassumption.
        rewrite restrict_sm_local, restrict_sm_all.
        red; intros. destruct (restrictD_Some _ _ _ _ _ H1). 
             apply local_in_all in H2; trivial.
             eapply restrictI_Some; eassumption.  
    eapply restrict_sm_preserves_globals.
      apply meminj_preserves_genv2blocks.
        apply meminj_preserves_genv2blocks in PG.
        eapply genvs_domain_eq_preserves; try eassumption.
        apply genvs_domain_eq_sym; eapply GDE_lemma.
      unfold vis. intuition. rewrite Glob. intuition.
      rewrite (genvs_domain_eq_isGlobal _ _ GDE_lemma); trivial.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
  intros [v' [A B]].
  exploit (eff_exec_straight_steps mu); try eassumption. 
    intros. simpl in TR.
    exploit transl_op_correct_eff; eauto. 
    intros [rs2 [P [Q R]]]. 
    assert (S: val_inject (as_inj (restrict_sm mu (vis mu))) v (rs2 (preg_of res))).
      eapply valinject_lessdef; try eassumption.
    exists rs2; split. eauto.
    split. eapply agree_set_undef_mreg; eassumption.
    simpl; congruence.
  intros [st' [CS' MS']].
  exists st', m2.
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  intuition. }

{ (* Mload *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  exploit agree_eval_addressing_inject; try eassumption.
  intros [a' [A B]].
  specialize (agree_sp_local _ _ _ _ AG); intros RSP. 
  assert (eval_addressing tge (rs0 ESP) addr rs0 ## (preg_of ## args) = Some a').
    rewrite <- A. 
    apply eval_addressing_preserved. exact symbols_preserved.
  clear A; rename H1 into A.
  exploit (Mem.loadv_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eexact H0. 
    apply B. 
  intros [v' [C D]].
  exploit (eff_exec_straight_steps mu). eassumption. eassumption. eassumption.
    eassumption. 
    intros. simpl in TR.
    exploit transl_load_correct_eff; eauto.
    intros [rs2 [P [Q R]]]. 
    exists rs2; split. eauto.
    split. eapply agree_set_undef_mreg. eassumption.
           instantiate (1:=dst). rewrite Q. eassumption. eauto.
    simpl; intros. congruence.
    assumption. 
   eassumption.
  intros [st' [CS' MS']].
  exists st', m2. 
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
         eassumption.
         intuition. }

{ (* Mstore *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  exploit agree_eval_addressing_inject; try eassumption.
  intros [a' [A B]].
  specialize (agree_sp_local _ _ _ _ AG); intros RSP. 
  assert (eval_addressing tge (rs0 ESP) addr rs0 ## (preg_of ## args) = Some a').
    rewrite <- A.
    apply eval_addressing_preserved. exact symbols_preserved.
  clear A; rename H1 into A.
  assert (val_inject (as_inj (restrict_sm mu (vis mu))) (rs src) (rs0 (preg_of src))).
      eapply preg_val; eassumption.
  exploit (Mem.storev_mapped_inject (as_inj mu));
    try eassumption.
    rewrite restrict_sm_all in B.
      eapply val_inject_incr; try eapply B. apply restrict_incr.
    rewrite restrict_sm_all in H1.
      eapply val_inject_incr; try eapply H1. apply restrict_incr.
  intros [m2' [C D]].
  exploit (eff_exec_straight_steps mu); try eassumption.
    intros. simpl in TR.
      exploit transl_store_correct_eff; eauto. (*rewrite <- RSP. eassumption. *)
      intros [rs2 [P Q]]. 
      exists rs2; split. eauto.
      split. eapply agree_undef_regs; eauto.  
      simpl; congruence.
  solve[inv MLF; constructor; eauto].
  intros [st' [CS' MS']].
  exists st', m2'.
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (storev_freshloc _ _ _ _ _ H0). intuition.
      apply extensionality; intros; rewrite (storev_freshloc _ _ _ _ _ C). intuition. 
      apply extensionality; intros; rewrite (storev_freshloc _ _ _ _ _ H0). intuition.
      apply extensionality; intros; rewrite (storev_freshloc _ _ _ _ _ C). intuition. 
  destruct a; inv H0.
  inv B. simpl in C.
  assert (SMV': sm_valid mu m' m2').
    split; intros. 
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
  split. split; intuition. eauto.
        eapply REACH_Store; try eassumption. 
          rewrite restrict_sm_all in H4.
            destruct (restrictD_Some _ _ _ _ _ H4); trivial.
          intros b' Hb'. rewrite getBlocks_char in Hb'. destruct Hb' as [off Hoff].
                  destruct Hoff; try contradiction.
                  specialize (agree_mregs _ _ _ _ AG src); intros AMR.
                   rewrite H0 in AMR; inv AMR.   
                   rewrite restrict_sm_all in H7. 
                   destruct (restrictD_Some _ _ _ _ _ H7); trivial.
  intros. rewrite restrict_sm_all in H4.
  specialize (StoreEffect_PropagateLeft chunk m (Vptr b i)); simpl. intros.
  assert (val_inject (restrict (as_inj mu) (vis mu)) 
                     (Vptr b i) (Vptr b2 (Int.add i (Int.repr delta)))).
    econstructor. eassumption. trivial.
  specialize (H2 _ _ H3 _ _ WD MEXT _ H5); simpl in H2.
  specialize (H2 _ _ C _ _ H0).
  split; try eassumption. 
  clear H2 H5. simpl in H0. destruct (eq_block b2 b0); simpl in *; inv H0.
  rewrite H5. eapply visPropagateR; eassumption. }

{ (* initial step *) 
  destruct PRE as [RC [PG [Glob [SMV WD]]]].
  eapply Genv.find_funct_ptr_transf_partial in TRANSF; eauto.
  destruct TRANSF as [tf [FND TRANSF']].
  revert TRANSF'. unfold transf_fundef, transf_partial_fundef.
  caseEq (transf_function f); simpl; try congruence.
  intros tfn TRANSL EQ. inversion EQ; clear EQ; subst tf.
  destruct WD as [VAL WD].
  exploit (alloc_parallel_intern' mu m m2 0 (4*z) m1 stk 0 (4*z)); 
    eauto; try solve[omega].
  intros [mu' [m2' [tsp0 [ALLOC' [INJ [INCR [ASINJ [X [? [? [? [? ?]]]]]]]]]]]].
  set (rs0 := (Pregmap.init Vundef) 
                  #PC <- (Vptr fb Int.zero)
                  #RA <- Vzero 
                  # ESP <- (Vptr tsp0 Int.zero)).
  exists (State rs0 (mk_load_frame tsp0 retty)).
  assert (VALSDEF': val_casted.vals_defined args' = true).
  { eapply val_casted.val_list_inject_defined; eauto. }
  assert (SIG: Mach.fn_sig f=fn_sig tfn).
  { revert TRANSL. unfold transf_function. unfold bind.
    destruct (transl_code' f (Mach.fn_code f) true); try solve[inversion 1].
    destruct (zlt (list_length_z c) Int.max_unsigned); try solve[inversion 1].
    inversion 1. simpl; auto. }
  assert (HASTY': Val.has_type_list args' (sig_args (fn_sig tfn))).
  { rewrite val_casted.val_has_type_list_func_charact in HASTY|-*.
    rewrite <-SIG. eapply val_casted.val_list_inject_hastype; eauto. }
  assert (ARGSLEN': args_len_rec args' (sig_args (fn_sig tfn)) = Some z).
  { exploit args_len_rec_succeeds; eauto. intros [? ?]; eauto.
    rewrite <-SIG in H7. exploit args_len_rec_inject; eauto.
    intros; subst; auto. rewrite <-SIG. auto. }
  assert (LEN: Zlength args=Zlength args').
  { clear - VINJ. induction VINJ; auto. 
    rewrite !Zlength_cons. rewrite IHVINJ. auto. }
  assert (STORE: exists m0', 
    store_args m2' tsp0 args' (sig_args (fn_sig tfn)) = Some m0').
  { unfold store_args; eapply store_args_rec_succeeds; eauto. 
    apply args_len_rec_bound in ARGSLEN'.
    assert (4*z <= 4*(2*Zlength args')) by omega.
    apply Zle_lt_trans with (m := 4*(2*Zlength args')); auto.
    unfold Int.max_unsigned in REP. rewrite <-LEN. omega. }
  destruct STORE as [m0' STORE].
  eexists; eexists; split. left.
    eapply effstep_plus_one. simpl. rewrite SIG. 
    solve[eapply asm_exec_initialize_call; eauto].
  assert (VIS': vis mu' stk=true).
  { rewrite sm_locally_allocatedChar in H3.
    unfold vis. destruct H3 as [_ [_ [-> _]]].
    rewrite !orb_true_iff. left. right. 
    erewrite freshloc_alloc; eauto. 
    solve[destruct (eq_block_refl stk) as [? ->]; auto]. }
  exists mu'.
  intuition.
  eapply store_args_rec_only_stores in H1. 
  eapply store_args_rec_only_stores in STORE. 
  eapply sm_locally_allocated_only_stores; eauto.
  solve[apply alloc_forward in H0; auto].
  solve[apply alloc_forward in ALLOC'; auto].
  unfold MATCH.
  intuition.
  rewrite SIG.
  apply match_states_call_internal with (f:=f); auto.
  solve[constructor].
  eapply store_args_inject with (args:=args) (args':=args'); eauto.
  apply val_list_inject_forall_inject in VINJ.
  apply forall_inject_val_list_inject.
  apply forall_vals_inject_restrictD in VINJ; auto.
  solve[eapply forall_vals_inject_intern_incr; eauto].
  apply local_in_all in ASINJ. eauto. auto.
  solve[rewrite SIG; auto].
  { (*agree*) 
    constructor. simpl. unfold rs0. rewrite Pregmap.gss. 
    apply val_inject_ptr with (delta := 0).
    rewrite restrict_sm_local. apply restrictI_Some; auto. 
    solve[rewrite Int.add_zero_l; auto].
    intros r. 
    assert (Regmap.init Vundef r = Vundef) as -> by (rewrite Regmap.gi; auto).
    constructor. }
  unfold rs0. rewrite Pregmap.gso. rewrite Pregmap.gss. simpl. constructor.
  congruence.
  constructor.
  apply restrictI_Some; auto. 
  apply store_args_rec_only_stores in H1. 
  eapply REACH_only_stores; eauto.
  intros b' GET. apply val_casted.getBlocks_encode_longs in GET.
  apply val_list_inject_forall_inject in VINJ.
  apply forall_vals_inject_restrictD' in VINJ. destruct VINJ as [VINJ VINJ'].
  apply VINJ' in GET. 
  solve[eapply intern_incr_vis; eauto].
  solve[destruct (intern_incr_meminj_preserves_globals_as_inj ge mu) 
          with (mu' := mu'); auto].
  (*last goal: globalfunction_ptr_inject *)
  red; intros. destruct (Glob _ _ H6). split; trivial.
  eapply intern_incr_as_inj; try eassumption.
  solve[destruct INCR as [_ [_ [_ [_ [_ [_ [<- _]]]]]]]; eauto].
  apply store_args_rec_only_stores in H1. 
  apply store_args_rec_only_stores in STORE. 
  eapply sm_valid_only_stores; eauto. }

{ (* Mcall_internal *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (f0 = f) by congruence.  subst f0.
  clear H0. rename H2 into CalleeF. 
  rename rs into ms; rename rs0 into rs.
  inv AT.
  clear H2.
  assert (NOOV: list_length_z (fn_code tf) <= Int.max_unsigned).
    eapply transf_function_no_overflow; eauto.
  destruct ros as [rf|fid]; simpl in H; monadInv H4.
+ (* Indirect Mcall internal*) 
  assert (ms rf = Vptr f' Int.zero).
    destruct (ms rf); try discriminate.
    revert H; predSpec Int.eq Int.eq_spec i Int.zero; intros; congruence.
  clear H.
  exploit ireg_val; try eassumption.
  rewrite H2; intros VI; inv VI.
  rewrite Int.add_zero_l in *.
  assert (val_inject (as_inj (restrict_sm mu (vis mu))) (Vptr f' Int.zero) (rs x0)).
    specialize (agree_mregs _ _ _ _ AG rf); simpl. 
    apply ireg_of_eq in EQ1.
    rewrite H2, EQ1; trivial.
  destruct (GFP _ _ CalleeF) as [mapped_f' GlobalBlock_f'].
  rewrite restrict_sm_all in H7.
  destruct (restrictD_Some _ _ _ _ _ H7) as [ZZ vis_f']; clear H7.
  rewrite mapped_f' in ZZ; apply eq_sym in ZZ; inv ZZ.
  clear H.  
  generalize (code_tail_next_int _ _ _ _ NOOV H5). intro CT1.
  assert (TCA: transl_code_at_pc ge (Vptr fb (Int.add ofs Int.one)) fb f c false tf x).
    econstructor; eauto.
  exploit return_address_offset_correct; eauto. intros; subst ra.
  eexists; eexists; eexists. 
  split. left. apply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
         eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
         simpl. eauto.
  destruct (GFP _ _ FIND) as [fb_mapped fb_globalblock].
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split.
    assert (MSTK: match_stack ge (restrict_sm mu (vis mu))
            (Stackframe fb sp (Vptr fb (Int.add ofs Int.one)) c :: s)).
      econstructor. eassumption. eassumption.
        rewrite restrict_sm_zero_or_localid; trivial.
        right. exists fb, (Int.add ofs Int.one). split; trivial.
          right. eapply (GFP _ _ FIND).
        assumption.
   split. 
     eapply match_states_call_internal; try eassumption.
       simpl. eapply agree_exten; eauto. intros. 
          rewrite Pregmap.gso; try solve [intros N; subst; discriminate].
          rewrite Pregmap.gso; try solve [intros N; subst; discriminate]. trivial.
        rewrite Pregmap.gss. rewrite <- H6. reflexivity.
        rewrite Pregmap.gso; try solve [intros N; subst; discriminate].
        rewrite Pregmap.gss. rewrite <- H0; simpl.
         econstructor.
         rewrite restrict_sm_all; eapply restrictI_Some. eassumption.
           unfold vis. rewrite (Glob _ fb_globalblock). intuition.
         rewrite Int.add_zero. trivial. 
     intuition.
   intuition. 

+ (* Direct call *)
  generalize (code_tail_next_int _ _ _ _ NOOV H5). intro CT1.
  assert (TCA: transl_code_at_pc ge (Vptr fb (Int.add ofs Int.one)) fb f c false tf x).
    econstructor; eauto.
  exploit return_address_offset_correct; eauto. intros; subst ra.
  eexists; eexists; eexists; split.
    left; apply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
      eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
      simpl. unfold symbol_offset. rewrite symbols_preserved. rewrite H. eauto.
  destruct (GFP _ _ FIND) as [fb_mapped fb_globalblock].
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. 
    assert (MSTK: match_stack ge (restrict_sm mu (vis mu)) 
                 (Stackframe fb sp (Vptr fb (Int.add ofs Int.one)) c :: s)).
       econstructor. eassumption. eassumption.
       rewrite restrict_sm_zero_or_localid; trivial.
       right. exists fb, (Int.add ofs Int.one). split; trivial.
         right. eapply (GFP _ _ FIND).
       assumption.  
    split.
      eapply match_states_call_internal; try eassumption.
        simpl. eapply agree_exten; eauto. intros. Simplifs.
        Simplifs. rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
            rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
            trivial.
        rewrite Pregmap.gss. trivial.
        simpl. rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
          rewrite Pregmap.gss. rewrite <- H0. simpl.
          econstructor.
          rewrite restrict_sm_all; eapply restrictI_Some. eassumption.
            unfold vis. rewrite (Glob _ fb_globalblock). intuition.
          rewrite Int.add_zero. trivial. 
      intuition.
    intuition. }

{ (* Mcall_external *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (f0 = f) by congruence.  subst f0.
  clear H0. rename H2 into CalleeF. 
  rename rs into ms; rename rs0 into rs.
  inv AT.
  clear H2.
  assert (NOOV: list_length_z (fn_code tf) <= Int.max_unsigned).
    eapply transf_function_no_overflow; eauto.
  destruct ros as [rf|fid]; simpl in H; monadInv H5.
+ (* Indirect Mcall external*) 
  assert (ms rf = Vptr f' Int.zero).
    destruct (ms rf); try discriminate.
    revert H; predSpec Int.eq Int.eq_spec i Int.zero; intros; congruence.
  clear H.

  exploit ireg_val; try eassumption.
  rewrite H2; intros VI; inv VI.
  rewrite Int.add_zero_l in *.
  destruct (GFP _ _ CalleeF) as [mapped_f' GlobalBlock_f'].
  rewrite restrict_sm_all in H8.
  destruct (restrictD_Some _ _ _ _ _ H8) as [ZZ vis_f']; clear H8.
  rewrite mapped_f' in ZZ; apply eq_sym in ZZ; inv ZZ.
  generalize (code_tail_next_int _ _ _ _ NOOV H6). intro CT1.
  assert (TCA: transl_code_at_pc ge (Vptr fb (Int.add ofs Int.one)) fb f c false tf x).
    econstructor; eauto.
  exploit return_address_offset_correct; eauto. intros; subst ra.
  destruct (functions_translated _ _ CalleeF) as [Tcallee [FFindCallee TransfCallee]].
  monadInv TransfCallee.
  exploit extcall_arguments_match.
    apply (restrict_sm_WD _ WD (vis mu)); trivial.
    instantiate (1:=(rs # RA <- (Val.add (Vptr fb ofs) Vone)) # PC <- (Vptr f' Int.zero)).
    eapply agree_exten; try eassumption.
       intros. Simplifs.
        rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
        rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
        trivial.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eassumption.
  intros [targs' [TExtcallArgs ArgsInj]].
  eexists; eexists; eexists. 
  split. left. eapply effstep_plus_two.
         eapply asm_effexec_step_internal. rewrite <- H0. reflexivity.
           eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
           simpl. eauto. 
         eapply asm_effexec_step_to_external. rewrite <- H7. Simplif.
           eassumption.
           rewrite <- H7, <- H0. eassumption.
  destruct (GFP _ _ FIND) as [fb_mapped fb_globalblock].
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split.
    split. 
      eapply match_states_call_external; try eassumption.
        { econstructor. eassumption. eassumption.
          rewrite restrict_sm_zero_or_localid; trivial.
          right. exists fb, (Int.add ofs Int.one). split; trivial.
            right. eapply (GFP _ _ FIND).
          assumption. }
        simpl. eapply agree_exten; eauto. intros. Simplifs.
        rewrite <- H7. Simplifs.
          rewrite Pregmap.gso; try solve [intros N; subst; discriminate].
          rewrite Pregmap.gso; try solve [intros N; subst; discriminate]. trivial.
        rewrite Pregmap.gss. rewrite <- H7. reflexivity.
        rewrite Pregmap.gso; try solve [intros N; subst; discriminate].
        rewrite Pregmap.gss. rewrite <- H0; simpl.
          econstructor.
            rewrite restrict_sm_all; eapply restrictI_Some. eassumption.
            unfold vis. rewrite (Glob _ fb_globalblock). intuition.
            rewrite Int.add_zero. trivial.
        rewrite <- H7, <- H0. assumption.  
     intuition.
  intuition.
+ (* Direct call *)
  simpl in H3. 
  generalize (code_tail_next_int _ _ _ _ NOOV H6). intro CT1.
  assert (TCA: transl_code_at_pc ge (Vptr fb (Int.add ofs Int.one)) fb f c false tf x).
    econstructor; eauto.
  exploit return_address_offset_correct; eauto. intros; subst ra.
  destruct (functions_translated _ _ CalleeF) as [Tcallee [FindTcallee TRANSCALLEE]].
  monadInv TRANSCALLEE.
  exploit extcall_arguments_match.
    apply (restrict_sm_WD _ WD (vis mu)); trivial.
    instantiate (1:=(rs # RA <- (Val.add (Vptr fb ofs) Vone)) # PC <- (Vptr f' Int.zero)).
    eapply agree_exten; try eassumption.
       intros. Simplifs.
      rewrite Pregmap.gso; try solve[intros N; subst; discriminate].
      rewrite Pregmap.gso; try solve[intros N; subst; discriminate]. trivial.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eassumption.
  intros [targs' [TExtcallArgs ArgsInj]].
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_two.
      eapply asm_effexec_step_internal. rewrite <- H0; reflexivity. 
        eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
        simpl. rewrite <- H0. unfold symbol_offset. rewrite symbols_preserved, H. reflexivity.
      eapply asm_effexec_step_to_external.
        Simplifs. 
        eassumption.
        eassumption.
  destruct (GFP _ _ FIND) as [fb_mapped fb_globalblock].
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. 
    assert (MSTK: match_stack ge (restrict_sm mu (vis mu)) 
                 (Stackframe fb sp (Vptr fb (Int.add ofs Int.one)) c :: s)).
       econstructor. eassumption. eassumption.
       rewrite restrict_sm_zero_or_localid; trivial.
       right. exists fb, (Int.add ofs Int.one). split; trivial.
         right. eapply (GFP _ _ FIND).
       assumption.  
    split.
      eapply match_states_call_external; try eassumption.
        simpl. eapply agree_exten; eauto. intros. Simplifs.
          Simplifs.
             rewrite Pregmap.gso; try solve[intros N; subst; discriminate]. trivial.
          Simplifs.
             rewrite Pregmap.gso; try solve[intros N; subst; discriminate]. trivial.
          rewrite Pregmap.gss. trivial.
            econstructor.
             rewrite restrict_sm_all; eapply restrictI_Some. eassumption.
              unfold vis. rewrite (Glob _ fb_globalblock). intuition.
          rewrite Int.add_zero. trivial.
      intuition.
    intuition. }

{ (* Mtailcall_internal *)
  inversion MS. subst tys0. subst args0. unfold lf0,lf1,lf2 in *. subst sp0. subst.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (f0 = f) by congruence.  subst f0.
  inv AT. clear H6 H0.
  assert (NOOV: list_length_z (fn_code tf) <= Int.max_unsigned).
    eapply transf_function_no_overflow; eauto.
  unfold load_stack in *.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
      apply restrict_sm_WD; try eassumption. trivial.
  specialize (sp_as_inj _ _ _ _ AG WDR). intros SPAI; inv SPAI.
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    simpl in H1. eexact H1.
    eassumption.
  intros [parent' [A B]].
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    simpl in H2. eexact H2.
    eassumption.
  intros [ra' [C D]].

  destruct (sp_spec_ptr _ _ _ SPlocal) as [tstk locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H13; trivial. 
  rewrite locSP in H13; apply eq_sym in H13; inv H13.
  rename H12 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  assert (XX: b2 = tstk /\ delta =0). 
    apply local_in_all in locSP; trivial.
    rewrite restrict_sm_all in H11.
    destruct (restrictD_Some _ _ _ _ _ H11) as [AI ?].
    rewrite AI in locSP. inv locSP. 
    split; trivial.
  destruct XX; subst. rewrite Int.add_zero, Zplus_0_r in *.
  clear H11 H10.
  exploit free_parallel_inject; try eapply H3.
    eassumption. eapply local_in_all; eassumption.    
  repeat rewrite Zplus_0_r. intros [m2' [E F]]. 
  destruct ros as [rf|fid]; simpl in H; monadInv H8.
+ (* Indirect Mtailcall_internal *)
  assert (rs rf = Vptr f' Int.zero).
    destruct (rs rf); try discriminate.
    revert H; predSpec Int.eq Int.eq_spec i Int.zero; intros; congruence.
  clear H.
  assert (val_inject (as_inj (restrict_sm mu (vis mu))) (Vptr f' Int.zero) (rs0 x0)).
    specialize (agree_mregs _ _ _ _ AG rf). rewrite H0.
    apply ireg_of_eq in EQ1. rewrite EQ1. trivial.
  destruct (GFP _ _ H4) as [mapped_f' GlobalBlock_f'].
  inv H. 
  rewrite restrict_sm_all in H11.
  destruct (restrictD_Some _ _ _ _ _ H11) as [ZZ vis_f']; clear H11.
  rewrite mapped_f' in ZZ; apply eq_sym in ZZ; inv ZZ.
  rewrite Int.add_zero in H10.
  generalize (code_tail_next_int _ _ _ _ NOOV H9). intro CT1.
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_star_trans. 
      eapply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
         eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
         simpl. rewrite <- RSP; simpl. rewrite C. rewrite A. rewrite E. eauto.
      apply effstep_star_one. eapply asm_effexec_step_internal. 
        transitivity (Val.add rs0#PC Vone). auto. rewrite <- H5. simpl. eauto.
         eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
        simpl. eauto.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
  split.
    { split.
      { econstructor; eauto.
        apply agree_set_other; auto. apply agree_nextinstr. apply agree_set_other; auto.
        eapply agree_change_sp. eassumption.
          eapply (parent_sp0_spec _ _ _ _ _ STACKS).
          inv MLF. instantiate (1 := tsp0). rewrite restrict_sm_local. solve[auto].
          assumption. apply restrict_sm_WD; trivial.
        Simplifs. rewrite Pregmap.gso; auto. 
        generalize (preg_of_not_SP rf). rewrite (ireg_of_eq _ _ EQ1). congruence. 
        inv MLF. constructor. auto.
      }
      intuition.
      eapply REACH_closed_free; try eassumption.
      split; intros. 
      eapply Mem.valid_block_free_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.valid_block_free_1; try eassumption.
        eapply SMV; assumption.
   }
  simpl. rewrite <- RSP; simpl. rewrite A, C, E.
     intros ? b z Hbz. rewrite orb_false_r in Hbz.
     apply FreeEffectD in Hbz; destruct Hbz as [? [VB Arith2]]; subst.
     destruct (local_DomRng _ WD _ _ _ locSP) as [SPlocalDom SPlocalTgt].              
     split. eapply visPropagate. eassumption.
              2: eapply local_in_all; eassumption.
              unfold vis; rewrite SPlocalDom; trivial.
     rewrite SPlocalTgt. congruence. 
+ (* Direct call *)
  generalize (code_tail_next_int _ _ _ _ NOOV H9). intro CT1.
  eexists; eexists; eexists; split.
    left. eapply effstep_plus_star_trans'.
             eapply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
              eapply functions_transl; eauto. eapply find_instr_tail; eauto.    
              simpl. rewrite <- RSP; simpl. rewrite C. rewrite A. rewrite E. eauto.
    apply effstep_star_one. eapply asm_effexec_step_internal. 
      transitivity (Val.add rs0#PC Vone). auto. rewrite <- H5. simpl. eauto.
      eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
      simpl. eauto.
    reflexivity.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
  split. 
    split.
      eapply match_states_call_internal; eauto.
      apply agree_set_other; auto. apply agree_nextinstr. apply agree_set_other; auto.
       eapply agree_change_sp; try eassumption.
         apply (parent_sp0_spec _ _ _ tsp0 _ STACKS).
         inv MLF. rewrite restrict_sm_local. solve[auto].
       Simplif. unfold symbol_offset. rewrite symbols_preserved. rewrite H. auto.
       inv MLF. constructor. auto.
    intuition.
      eapply REACH_closed_free; try eassumption.
      split; intros. 
        eapply Mem.valid_block_free_1; try eassumption.
          eapply SMV; assumption.
        eapply Mem.valid_block_free_1; try eassumption.
          eapply SMV; assumption.
  simpl. rewrite <- RSP; simpl. rewrite A, C, E.
     intros ? b z Hbz. rewrite orb_false_r in Hbz.
     apply FreeEffectD in Hbz; destruct Hbz as [? [VB Arith2]]; subst.
     destruct (local_DomRng _ WD _ _ _ locSP) as [SPlocalDom SPlocalTgt].              
     split. eapply visPropagate. eassumption.
              2: eapply local_in_all; eassumption.
              unfold vis; rewrite SPlocalDom; trivial.
     rewrite SPlocalTgt. congruence.  }

{ (* Mtailcall_external *)
  inversion MS. subst tys0. subst args0. unfold lf0,lf1,lf2 in *. subst sp0. subst.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (f0 = f) by congruence.  subst f0.
  inv AT. clear H7 H0.
  assert (NOOV: list_length_z (fn_code tf) <= Int.max_unsigned).
    eapply transf_function_no_overflow; eauto.
  unfold load_stack in *.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
      apply restrict_sm_WD; try eassumption. trivial.
  specialize (sp_as_inj _ _ _ _ AG WDR). intros SPAI; inv SPAI.
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    simpl in H1. eexact H1.
    eassumption.
  intros [parent' [A B]].
  exploit (Mem.load_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    simpl in H2. eexact H2.
    eassumption.
  intros [ra' [C D]].

  destruct (sp_spec_ptr _ _ _ SPlocal) as [tstk locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H14; trivial. 
  rewrite locSP in H14; apply eq_sym in H14; inv H14.
  rename H13 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  assert (XX: b2 = tstk /\ delta =0). 
    apply local_in_all in locSP; trivial.
    rewrite restrict_sm_all in H12.
    destruct (restrictD_Some _ _ _ _ _ H12) as [AI ?].
    rewrite AI in locSP. inv locSP. 
    split; trivial.
  destruct XX; subst. rewrite Int.add_zero, Zplus_0_r in *.
  clear H12 H11.
  exploit free_parallel_inject; eauto.
    eapply local_in_all; eassumption.
  repeat rewrite Zplus_0_r. intros [m2' [E F]].
  simpl in *. 
  destruct ros as [rf|fid]; simpl in H; monadInv H9.
+ (* Indirect Mtailcall_external *) 
  assert (rs rf = Vptr f' Int.zero).
    destruct (rs rf); try discriminate.
    revert H; predSpec Int.eq Int.eq_spec i Int.zero; intros; congruence.
  clear H.
  assert (val_inject (as_inj (restrict_sm mu (vis mu))) (Vptr f' Int.zero) (rs0 x0)).
    specialize (agree_mregs _ _ _ _ AG rf). rewrite H0.
    apply ireg_of_eq in EQ1. rewrite EQ1. trivial.
  destruct (GFP _ _ H4) as [mapped_f' GlobalBlock_f'].
  inv H. 
  rewrite restrict_sm_all in H12.
  destruct (restrictD_Some _ _ _ _ _ H12) as [ZZ vis_f']; clear H12.
  rewrite mapped_f' in ZZ; apply eq_sym in ZZ; inv ZZ.
  rewrite Int.add_zero in H11.
  generalize (code_tail_next_int _ _ _ _ NOOV H10). intro CT1.
  destruct (functions_translated _ _ H4) as [Tcallee [FFindCallee TransfCallee]].
  monadInv TransfCallee.
  assert (AG1: agree (restrict_sm mu (vis mu)) rs (parent_sp0 sp1 s)
            (nextinstr (rs0 # ESP <- parent') # RA <- ra') # PC <-
            (nextinstr (rs0 # ESP <- parent') # RA <- ra' x0)).
  { apply agree_set_other; auto. apply agree_nextinstr. 
      apply agree_set_other; auto.
    eapply agree_change_sp; try eassumption.
       apply (parent_sp0_spec _ _ _ tsp0 _ STACKS). 
       inv MLF. solve[rewrite restrict_sm_local; auto]. }
  exploit extcall_arguments_match.
    eapply WDR.
    eapply AG1.
    rewrite restrict_sm_all. eapply inject_restrict. eassumption.
        eapply REACH_closed_free; eassumption.
    eapply H5.
  intros [targs' [TExtcallArgs ArgsInj]].
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_trans. 
      eapply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
         eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
         simpl. rewrite <- RSP. simpl.
         rewrite C. rewrite A. rewrite E. eauto.
      eapply effstep_plus_two. eapply asm_effexec_step_internal. 
        transitivity (Val.add rs0#PC Vone). auto. rewrite <- H6. simpl. eauto.
         eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
        simpl. eauto.
      eapply asm_effexec_step_to_external.
        unfold nextinstr. Simplif.
         rewrite Pregmap.gso.
         rewrite Pregmap.gso.
         rewrite Pregmap.gso. rewrite <- H11. reflexivity.
         generalize (preg_of_not_SP rf). rewrite (ireg_of_eq _ _ EQ1). congruence. 
         apply ireg_of_eq in EQ1. intros N.
           rewrite N in *. clear N. destruct rf; discriminate.
         apply ireg_of_eq in EQ1. intros N.
           rewrite N in *. clear N. destruct rf; discriminate.
         eassumption.
         eassumption.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
  split. 
    split.
      eapply match_states_call_external; eauto.
        Simplifs. rewrite Pregmap.gso; auto. 
        generalize (preg_of_not_SP rf). rewrite (ireg_of_eq _ _ EQ1). congruence.
        inv MLF. constructor; auto.
      intuition.
      eapply REACH_closed_free; try eassumption.
      split; intros. 
        eapply Mem.valid_block_free_1; try eassumption.
          eapply SMV; assumption.
        eapply Mem.valid_block_free_1; try eassumption.
          eapply SMV; assumption.
  simpl. rewrite <- RSP; simpl. rewrite A, C, E.
     intros ? b z Hbz. rewrite orb_false_r in Hbz.
     apply FreeEffectD in Hbz; destruct Hbz as [? [VB Arith2]]; subst.
     destruct (local_DomRng _ WD _ _ _ locSP) as [SPlocalDom SPlocalTgt].              
     split. eapply visPropagate. eassumption.
              2: eapply local_in_all; eassumption.
              unfold vis; rewrite SPlocalDom; trivial.
     rewrite SPlocalTgt. congruence.
+ (* Direct call *)
  generalize (code_tail_next_int _ _ _ _ NOOV H10). intro CT1.
  destruct (functions_translated _ _ H4) as [Tcallee [TFindCaller TransCallee]].
  monadInv TransCallee.
  assert (AG1: agree (restrict_sm mu (vis mu)) rs (parent_sp0 sp1 s)
    (nextinstr (rs0 # ESP <- parent') # RA <- ra') # PC <-
    (symbol_offset tge fid Int.zero)).
  { apply agree_set_other; auto. apply agree_nextinstr. apply agree_set_other; auto.
    eapply agree_change_sp; eauto.
      eapply (parent_sp0_spec _ _ _ tsp0 _ STACKS).
      inv MLF. solve[rewrite restrict_sm_local; auto]. }
  exploit extcall_arguments_match.
    apply (restrict_sm_WD _ WD (vis mu)); trivial.
    apply AG1.
    rewrite restrict_sm_all; eapply inject_restrict; try eapply F; trivial.
    eapply REACH_closed_free; eassumption.
    eassumption.
  intros [targs' [TExtcallArgs ArgsInj]].
  eexists; eexists; eexists; split.
    left. eapply effstep_plus_trans'.
             eapply effstep_plus_one. eapply asm_effexec_step_internal. 
               rewrite <- H6. eauto.
             eapply functions_transl; eauto. eapply find_instr_tail; eauto.    
             simpl. rewrite <- RSP; simpl. rewrite C. rewrite A. rewrite E. eauto.
    eapply effstep_plus_two. eapply asm_effexec_step_internal. 
      transitivity (Val.add rs0#PC Vone). auto. rewrite <- H6. simpl. eauto.
      eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
      simpl. eauto.
    eapply asm_effexec_step_to_external.
      unfold symbol_offset. rewrite symbols_preserved, H.
      Simplif.
      eassumption.
      eassumption.
    reflexivity.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H3). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
  split. 
    split.
      eapply match_states_call_external; eauto.
        Simplif. 
        unfold symbol_offset. rewrite symbols_preserved, H. trivial.
    inv MLF. constructor; auto.
    intuition.
    eapply REACH_closed_free; try eassumption.
    split; intros. 
      eapply Mem.valid_block_free_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.valid_block_free_1; try eassumption.
        eapply SMV; assumption.
  simpl. rewrite <- RSP; simpl. rewrite A, C, E.
     intros ? b z Hbz. rewrite orb_false_r in Hbz.
     apply FreeEffectD in Hbz; destruct Hbz as [? [VB Arith2]]; subst.
     destruct (local_DomRng _ WD _ _ _ locSP) as [SPlocalDom SPlocalTgt].              
     split. eapply visPropagate. eassumption.
              2: eapply local_in_all; eassumption.
              unfold vis; rewrite SPlocalDom; trivial.
     rewrite SPlocalTgt. congruence. }

{ (* builtin*) 
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
      assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
        rewrite <- restrict_sm_all.
        eapply restrict_sm_preserves_globals; try eassumption.
          unfold vis. intuition.
  inv H. inv AT. monadInv H4. 
  exploit functions_transl; eauto. intro FN.
  generalize (transf_function_no_overflow _ _ H3); intro NOOV.
  exploit (inlineable_extern_inject _ _ GDE_lemma); eauto.
    unfold ge, tge. 
    eapply Genv.find_symbol_transf_partial; eauto.
    rewrite <- restrict_sm_all. eapply decode_longs_inject.
    eapply preg_vals; eauto.
  intros [mu' [vres' [tm' [EC [VINJ [MINJ' [UNMAPPED [OUTOFREACH 
           [INCR [SEPARATED [LOCALLOC [WD' [VAL' RC']]]]]]]]]]]]].
  eexists; eexists; eexists. 
  split. left. eapply effstep_plus_one.
           eapply asm_effexec_step_builtin. eauto. eauto.
            eapply find_instr_tail; eauto.
           econstructor. eassumption.
            reflexivity. auto. eauto.
  exists mu'.
  split; trivial. 
  split; trivial. 
  split; trivial. 
  split.
    split. econstructor; eauto.
      eapply match_stack_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption. 
      instantiate (1 := x).
      unfold nextinstr_nf, nextinstr. rewrite Pregmap.gss.
      rewrite undef_regs_other. rewrite set_pregs_other_2. rewrite undef_regs_other_2.
      rewrite <- H. simpl. econstructor; eauto.
      eapply code_tail_next_int; eauto.
      rewrite preg_notin_charact. intros. auto with asmgen.
      rewrite preg_notin_charact. intros. auto with asmgen.
      auto with asmgen.
      simpl; intros. intuition congruence.
      apply agree_nextinstr_nf. eapply agree_set_mregs; auto.
      eapply agree_intern_incr.
         Focus 3. eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; trivial.
       eapply agree_undef_regs; eauto.
       intros; eapply undef_regs_other_2; eauto. 
      eapply encode_long_inject. rewrite restrict_sm_all; eassumption. 
      congruence.

      eapply sp_spec_intern_incr; eassumption.
      inv MLF; constructor. 
      generalize INCR as INCR'; intro.
      apply intern_incr_local in INCR.
      apply restrictD_Some in SP. destruct SP as [X Y].
      apply restrictI_Some. 
      apply INCR; auto.
      solve[eapply intern_incr_vis in INCR'; eauto].
    intuition. 
    eapply meminj_preserves_incr_sep. eapply PG. eassumption. 
             apply intern_incr_as_inj; trivial.
             apply sm_inject_separated_mem; eassumption.
    red; intros bb fbb Hbb. destruct (GFP _ _ Hbb).
          split; trivial.
          eapply intern_incr_as_inj; eassumption.    
    assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INCR.
          rewrite <- FRG. eapply (Glob _ H4).
    intros. 
      eapply BuiltinEffect_Propagate with (tge0:=tge); try eassumption.
      eapply decode_longs_inject. rewrite <- restrict_sm_all.
        eapply preg_vals; apply AG. }

(* - annot: later*)

{ (* Mgoto *)
  assert (f0 = f) by congruence. subst f0.
  inv AT. monadInv H4.
  exploit find_label_goto_label; eauto. intros [tc' [rs' [GOTO [AT2 INV]]]].
  exists (State rs' tlf), m2; eexists; split. left.
    apply effstep_plus_one. econstructor; eauto.
    eapply functions_transl; eauto.
    eapply find_instr_tail; eauto.
    simpl; eauto.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition. 
    econstructor; eauto.
      eapply agree_exten. eassumption.
       intros r Dr. eapply INV. intros Hr; subst. inv Dr.
      congruence.
  simpl. intuition.  }

{ (* Mcond true *)
  assert (f0 = f) by congruence. subst f0.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  exploit eval_condition_inject.
    eapply preg_vals; eauto.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eauto.
  intros EC.
  exploit eff_exec_straight_steps_goto; eauto.
    intros. simpl in TR.
    destruct (transl_cond_correct_eff tge tf cond args _ _ rs0 m2 TR)
    as [rs' [A [B C]]]. 
    rewrite EC in B.
    destruct (testcond_for_condition cond); simpl in *.
    (* simple jcc *)
      exists (Pjcc c1 lbl); exists k; exists rs'.
      split. eexact A.
      split. eapply agree_exten; eauto. 
      simpl. rewrite B. auto.
    (* jcc; jcc *)
      destruct (eval_testcond c1 rs') as [b1|] eqn:TC1;
      destruct (eval_testcond c2 rs') as [b2|] eqn:TC2; inv B.
      destruct b1.   
      (* first jcc jumps *)
      exists (Pjcc c1 lbl); exists (Pjcc c2 lbl :: k); exists rs'.
      split. eexact A.
      split. eapply agree_exten; eauto. 
      simpl. rewrite TC1. auto.
      (* second jcc jumps *)
      exists (Pjcc c2 lbl); exists k; exists (nextinstr rs').
      split. eapply eff_exec_straight_trans. eexact A. 
      eapply eff_exec_straight_one. simpl. rewrite TC1. auto. auto.
      reflexivity.
      intuition.
      split. eapply agree_exten; eauto.
      intros; Simplifs.
      simpl. rewrite eval_testcond_nextinstr. rewrite TC2.
      destruct b2; auto || discriminate.
    (* jcc2 *)
      destruct (eval_testcond c1 rs') as [b1|] eqn:TC1;
      destruct (eval_testcond c2 rs') as [b2|] eqn:TC2; inv B.
      destruct (andb_prop _ _ H3). subst. 
      exists (Pjcc2 c1 c2 lbl); exists k; exists rs'.
      split. eexact A.
      split. eapply agree_exten; eauto. 
      simpl. rewrite TC1; rewrite TC2; auto.
  intros [st' [CS' MS']].
  exists st', m2. 
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  intuition. }

{ (* Mcond false *)
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  exploit eval_condition_inject.
    eapply preg_vals; eauto.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eauto.
  intros EC. 
  exploit eff_exec_straight_steps; try eassumption. instantiate (3:=EmptyEffect).
    intros. simpl in TR.
    destruct (transl_cond_correct_eff tge tf cond args _ _ rs0 m2 TR)
    as [rs' [A [B C]]]. 
    rewrite EC in B.
    destruct (testcond_for_condition cond); simpl in *.
    (* simple jcc *)
      econstructor; split.
      eapply eff_exec_straight_trans. eexact A. 
      apply eff_exec_straight_one. simpl. rewrite B. eauto. auto. 
      reflexivity. simpl; intuition.
      split. apply agree_nextinstr. eapply agree_exten; eauto.
      simpl; congruence.
    (* jcc ; jcc *)
      destruct (eval_testcond c1 rs') as [b1|] eqn:TC1;
      destruct (eval_testcond c2 rs') as [b2|] eqn:TC2; inv B.
      destruct (orb_false_elim _ _ H1); subst.
      econstructor; split.
      eapply eff_exec_straight_trans. eexact A. 
      eapply eff_exec_straight_two. simpl. rewrite TC1. eauto. auto. 
      simpl. rewrite eval_testcond_nextinstr. rewrite TC2. eauto. auto. auto.
      reflexivity. simpl; intuition.
      split. apply agree_nextinstr. apply agree_nextinstr. eapply agree_exten; eauto.
      simpl; congruence.
    (* jcc2 *)
      destruct (eval_testcond c1 rs') as [b1|] eqn:TC1;
      destruct (eval_testcond c2 rs') as [b2|] eqn:TC2; inv B.
      exists (nextinstr rs'); split.
      eapply eff_exec_straight_trans. eexact A. 
      apply eff_exec_straight_one. simpl. 
      rewrite TC1; rewrite TC2. 
      destruct b1. simpl in *. subst b2. auto. auto.
      auto.
      reflexivity. simpl; intuition.
      split. apply agree_nextinstr. eapply agree_exten; eauto.
      rewrite H1; congruence.
  intros [st' [CS' MS']].
  exists st', m2.
  eexists; split. left; eassumption.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
  intuition. }

{ (* Mjumptable *)
  assert (f0 = f) by congruence. subst f0.
  inv AT. monadInv H6. 
  exploit functions_transl; eauto. intro FN.
  generalize (transf_function_no_overflow _ _ H5); intro NOOV.
  exploit find_label_goto_label; eauto. 
  intros [tc' [rs' [A [B C]]]].
  exploit ireg_val; eauto. rewrite H. intros LD; inv LD.
  eexists; eexists; eexists; split. left.
    apply effstep_plus_one. econstructor; eauto.  
    eapply find_instr_tail; eauto. 
    simpl. rewrite <- H9. unfold Mach.label in H0; unfold label; rewrite H0. eauto.
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. split; intuition.
           econstructor; eauto. 
Transparent destroyed_by_jumptable.   
      simpl. eapply agree_exten; eauto.
        intros r Dr. apply C. intros; subst. inv Dr.
      congruence.
  intuition. }

{ (* Mreturn *)
  inversion MS. subst tys0. subst args0. unfold lf0,lf1,lf2 in *. subst sp0. subst.
  assert (f0 = f) by congruence. subst f0.
  inv AT. 
  assert (NOOV: list_length_z (fn_code tf) <= Int.max_unsigned).
    eapply transf_function_no_overflow; eauto.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].

  destruct (sp_spec_ptr _ _ _ SPlocal) as [tstk locSP]. 
  specialize (agree_sp_local _ _ _ _ AG); intros RSP.
  inv RSP. rewrite restrict_sm_local' in H11; trivial. 
  rewrite locSP in H11; apply eq_sym in H11; inv H11.
  rename H10 into RSP. rewrite Int.add_zero in RSP.
  specialize (local_of_vis _ _ _ _ locSP WD); intros visSP.
  unfold load_stack in *.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
     eapply (restrict_sm_WD _ WD ); trivial. 
  assert (AiSTK: as_inj mu stk = Some (tstk, 0)).
        apply local_in_all in locSP; eassumption.    
  exploit (Mem.loadv_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eexact H0.
    simpl. econstructor.
      rewrite restrict_sm_all. apply restrictI_Some; eassumption.
    rewrite Int.add_zero. reflexivity.
  intros [parent' [A B]]. 
  exploit (Mem.loadv_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eexact H1.
    simpl. econstructor.
      rewrite restrict_sm_all. apply restrictI_Some; eassumption.
    rewrite Int.add_zero. reflexivity.
  intros [ra' [C D]]. 
  exploit free_parallel_inject; eauto.
  simpl. rewrite Zplus_0_r. intros [m2' [E F]].
  monadInv H6.
  exploit code_tail_next_int; eauto. intro CT1.
  eexists; eexists; eexists; split. left.
    eapply effstep_plus_star_trans.
      eapply effstep_plus_one. eapply asm_effexec_step_internal. eauto.
        eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
        simpl. rewrite <- RSP. simpl. simpl in C. rewrite C. 
          simpl in A. rewrite A. (* rewrite <- (sp_val _ _ _ AG).*)
          rewrite E. eauto.
    apply effstep_star_one. eapply asm_effexec_step_internal. 
      transitivity (Val.add rs0#PC Vone). auto. rewrite <- H3. simpl. eauto.
      eapply functions_transl; eauto. eapply find_instr_tail; eauto. 
      simpl. eauto. 
  exists mu. 
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H2). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ H2). intuition.
      apply extensionality; intros; rewrite (freshloc_free _ _ _ _ _ E). intuition.
  split.
    split.
      constructor; eauto. 
        apply agree_set_other; auto. apply agree_nextinstr. apply agree_set_other; auto.
          eapply agree_change_sp; eauto. 
            eapply (parent_sp0_spec _ _ _ tsp0 _ STACKS). 
            inv MLF. solve[rewrite restrict_sm_local; auto].
            inv MLF. solve[constructor; auto].
     intuition.
     eapply REACH_closed_free; try eassumption.
     split; intros. 
       eapply Mem.valid_block_free_1; try eassumption.
         eapply SMV; assumption.
       eapply Mem.valid_block_free_1; try eassumption.
         eapply SMV; assumption.
  simpl. intros. rewrite orb_false_r, <- RSP in H6.
    simpl in H6. simpl in *. rewrite C, A, E in H6.
    destruct (FreeEffectD _ _ _ _ _ _ H6) as [? [VB OFS]]; subst.
    split. eapply visPropagate; eassumption.
    eapply FreeEffect_PropagateLeft; eassumption. }

{ (*internal function *)
  inversion MS. subst tys0. subst args0. unfold lf0,lf1,lf2 in *. subst sp0. subst.
  rewrite INT in H. inv H.
  exploit functions_translated; eauto. intros [tf [A B]]. monadInv B.
  generalize EQ; intros EQ'. monadInv EQ'. rewrite transl_code'_transl_code in EQ0.
  destruct (zlt (list_length_z x0) Int.max_unsigned); inversion EQ1. clear EQ1.
  unfold store_stack in *.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
     eapply (restrict_sm_WD _ WD ); trivial. 
  exploit alloc_parallel_intern; try eassumption. apply Z.le_refl. apply Z.le_refl.
  intros [mu' [tm1 [tstk [TAlloc [INJ1 [INC [STK [Mu'Mu 
         [SEP [LOCALLOC [WD' [WMV' RC1]]]]]]]]]]]]. 
  assert (stk_local: local_of (restrict_sm mu' (vis mu')) stk = Some (tstk, 0)).
    rewrite restrict_sm_local'; trivial.
    destruct (joinD_Some _ _ _ _ _ STK) as [EXT | [_ LOC]]; trivial.
    assert (EXT': extern_of mu = extern_of mu') by eapply INC.
    rewrite <- EXT' in EXT; clear EXT'.
    apply extern_in_all in EXT; trivial. 
    destruct (as_inj_DomRng _ _ _ _ EXT WD).
    elim (Mem.fresh_block_alloc _ _ _ _ _ H0).
    eapply SMV. apply H.
  exploit Mem.store_mapped_inject; try eapply INJ1. eapply H1. eassumption.
    eapply val_inject_incr.
      eapply (intern_incr_as_inj _ _ INC WD').
    eapply val_inject_incr.
       2: apply (sp_as_inj _ _ _ _ AG WDR).
    rewrite restrict_sm_all. apply restrict_incr. 
  rewrite Zplus_0_r, Int.add_zero_l. intros [tm0 [ST1 INJ0]].
  exploit Mem.store_mapped_inject; try eapply INJ0. eapply H2. eassumption.
    instantiate (1:=rs0 RA). 
    eapply val_inject_incr.
      eapply (intern_incr_as_inj _ _ INC WD').
    eapply val_inject_incr; try eassumption.
      rewrite restrict_sm_all. apply restrict_incr. 
  rewrite Zplus_0_r, Int.add_zero_l. intros [tm3 [ST2 INJ3]].
  eexists; eexists; eexists; split.
    left. apply effstep_plus_one. econstructor; eauto. 
     subst x; simpl.
     rewrite Int.unsigned_zero. simpl. eauto.
     simpl. rewrite TAlloc . simpl in ST1.
      rewrite Int.add_zero_l.
      destruct AG as [AG1 AG2]. rewrite ST1.
      rewrite Int.add_zero_l.
      simpl in ST2. rewrite ST2.
      eauto.
  exists mu'.
  split; trivial.
  split; trivial.
  split. rewrite sm_locally_allocatedChar.
    rewrite sm_locally_allocatedChar in LOCALLOC.
    assert (freshloc m m3 = freshloc m m1).
      extensionality b. rewrite <- (freshloc_trans m m1).
      rewrite <- (freshloc_trans m1 m0 m3).
      rewrite (storev_freshloc _ _ _ _ _ H1).
      rewrite (storev_freshloc _ _ _ _ _ H2). intuition.
      eapply store_forward; eapply H1.
      eapply store_forward; eapply H2.
      eapply alloc_forward; eassumption.
      eapply mem_forward_trans. 
      eapply store_forward; eapply H1.
      eapply store_forward; eapply H2.
    rewrite H.
    assert (freshloc m2 tm3 = freshloc m2 tm1).
      extensionality b. rewrite <- (freshloc_trans m2 tm1).
      rewrite <- (freshloc_trans tm1 tm0 tm3).
      rewrite (store_freshloc _ _ _ _ _ _ ST1).
      rewrite (store_freshloc _ _ _ _ _ _ ST2). intuition.
      eapply store_forward; eapply ST1.
      eapply store_forward; eapply ST2.
      eapply alloc_forward; eassumption.
      eapply mem_forward_trans. 
      eapply store_forward; eapply ST1.
      eapply store_forward; eapply ST2.
    rewrite H4.
    assumption.
  split.
    split. econstructor; eauto.
      eapply match_stack_intern_incr; try eassumption.
        apply restrict_sm_intern_incr; trivial.
      unfold nextinstr. rewrite Pregmap.gss.
        repeat rewrite Pregmap.gso; auto with asmgen. 
      rewrite ATPC. simpl. constructor; eauto.
        subst x. unfold fn_code. eapply code_tail_next_int. 
          rewrite list_length_z_cons. omega. 
      constructor.
     { (*agree *) subst sp.
       apply agree_nextinstr. eapply agree_change_sp; eauto.
Transparent destroyed_at_function_entry.
       apply agree_undef_regs with rs0; eauto.
         eapply agree_intern_incr; try eassumption.
         apply restrict_sm_WD; trivial. 
       apply restrict_sm_intern_incr; try eassumption; trivial.
       simpl; intros. apply Pregmap.gso; auto with asmgen. tauto. 
       exists stk, Int.zero, tstk; split; trivial.
       econstructor. eapply local_in_all; try eassumption.
        apply restrict_sm_WD; trivial. 
        rewrite Int.add_zero. trivial.
        apply restrict_sm_WD; trivial. }     
     intros. unfold nextinstr. simpl.
       rewrite Pregmap.gso. rewrite Pregmap.gso. rewrite Pregmap.gss.
       eapply val_inject_incr.
         2: apply (sp_as_inj _ _ _ _ AG WDR).
         rewrite restrict_sm_all. rewrite restrict_sm_all. 
           apply intern_incr_restrict; trivial.
       congruence. congruence.
     subst sp. exists stk, Int.zero, tstk. split; trivial. 
       rewrite restrict_sm_local' in stk_local; trivial. 
     assert (stkVIS: vis mu' stk = true).
     { unfold vis. rewrite restrict_sm_local' in stk_local; trivial.
       destruct (local_DomRng _ WD' _ _ _ stk_local) as [DS DT].
       rewrite DS; trivial. }
    inv MLF. constructor; auto. 
    { generalize INC as INCR'; intro.
      apply intern_incr_local in INC.
      apply restrictD_Some in SP. destruct SP as [X Y].
      apply restrictI_Some. apply INC; auto.
      solve[eapply intern_incr_vis in INCR'; eauto]. }

     assert (parentra_VIS: forall b' (Hb' : getBlocks (parent_ra s :: nil) b' = true), 
              vis mu' b' = true).
     { intros. apply getBlocks_char in Hb'.
       destruct Hb'. destruct H; try contradiction.
       destruct (parent_ra_spec _ _ _ STACKS).
       rewrite H in H4; discriminate.
       eapply (intern_incr_vis _ _ INC). unfold vis.
       destruct H4 as [bb [z [PAR [[tb LOC] | GL]]]]; rewrite PAR in H; inv H.
       rewrite restrict_sm_local' in LOC; trivial.
       destruct (local_DomRng _ WD _ _ _ LOC). intuition. intuition. }

    intuition.
    eapply REACH_Store. eapply H2. 
      rewrite restrict_sm_local in stk_local.
      apply restrictD_Some in stk_local. destruct stk_local; auto. 
      eassumption.
    { eapply REACH_Store. eapply H1. 
      rewrite restrict_sm_local in stk_local.
      apply restrictD_Some in stk_local. destruct stk_local; auto. 
      intros. eapply (intern_incr_vis _ _ INC). unfold vis. 
      destruct (parent_sp0_spec _ _ sp1 tsp0 _ STACKS) as [bb [z [tbb [PARSP LOC]]]].
      inv MLF. solve[rewrite restrict_sm_local; auto].
      rewrite PARSP in H4.
      apply getBlocks_char in H4. destruct H4. 
      destruct H4; try contradiction. inv H4.
      rewrite restrict_sm_local' in LOC; trivial.
      destruct (local_DomRng _ WD _ _ _ LOC). intuition.
      assumption. }
    eapply meminj_preserves_incr_sep. eapply PG. eassumption. 
             apply intern_incr_as_inj; trivial.
             apply sm_inject_separated_mem; eassumption.
    red; intros bb fbb Hbb. destruct (GFP _ _ Hbb).
          split; trivial.
          eapply intern_incr_as_inj; eassumption.
    assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INC.
          rewrite <- FRG. eapply (Glob _ H4).
    apply sm_locally_allocatedChar in LOCALLOC. 
      rewrite (freshloc_alloc _ _ _ _ _ H0) in LOCALLOC.
      rewrite (freshloc_alloc _ _ _ _ _ TAlloc) in LOCALLOC.
      destruct LOCALLOC as [DS [DT _]].
      split; intros.
        unfold DOM in H4. rewrite DS in H4.
          eapply Mem.store_valid_block_1; try eapply H2.
          eapply Mem.store_valid_block_1; try eapply H1.
          destruct (eq_block b1 stk); subst; simpl in *.
            apply (Mem.valid_new_block _ _ _ _ _ H0).
            apply (Mem.valid_block_alloc _ _ _ _ _ H0).
              eapply SMV. rewrite orb_false_r in H4; trivial.
        unfold RNG in H4. rewrite DT in H4.
          eapply Mem.store_valid_block_1; try eapply ST2.
          eapply Mem.store_valid_block_1; try eapply ST1.
          destruct (eq_block b2 tstk); subst; simpl in *.
            apply (Mem.valid_new_block _ _ _ _ _ TAlloc).
            apply (Mem.valid_block_alloc _ _ _ _ _ TAlloc).
              eapply SMV. rewrite orb_false_r in H4; trivial.
  simpl. intuition. }

(*external function *) 
{ destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
  { rewrite <- restrict_sm_all.
    eapply restrict_sm_preserves_globals; try eassumption.
    unfold vis. intuition. }
  inv H0.
  exploit (inlineable_extern_inject _ _ GDE_lemma); eauto.
    eapply Genv.find_symbol_transf_partial; eauto.
    apply (EFhelpers _ _ OBS).
    apply decode_longs_inject. rewrite restrict_sm_all in ArgsInj. eapply ArgsInj.
  intros [mu' [vres' [tm' [EC [VINJ [MINJ' [UNMAPPED [OUTOFREACH 
         [A [B [C [D [E F]]]]]]]]]]]]].
  eexists; eexists; eexists.
  split.
  left.
  apply effstep_plus_one.
  econstructor; eauto.
  exploit Genv.find_funct_ptr_transf_partial; eauto.
  intros [tf' [X Y]]. unfold tge. rewrite X. simpl in Y. solve[inv Y; auto].
  eapply external_call'_intro; eauto. 
  exists mu'.
  intuition.
  split.
  constructor; auto.
      eapply match_stack_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption. 
      apply agree_set_other; auto.
      apply agree_set_mregs; auto.
      eapply agree_intern_incr.
         Focus 3. eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; trivial.
         auto.
      apply encode_long_inject; auto. 
      rewrite restrict_sm_all; auto.
      eapply val_inject_incr in ATLR. eauto.
      eapply intern_incr_as_inj; eauto.
      apply restrict_sm_intern_incr; auto.
      eapply restrict_sm_WD in D; eauto.
      inv MLF. constructor. 
      apply restrictD_Some in SP. destruct SP as [X Y]. 
      apply restrictI_Some; auto.
      apply intern_incr_local in A. apply A; auto.
      solve[eapply intern_incr_vis in A; eauto].
    intuition.
    eapply meminj_preserves_incr_sep. eapply PG. eassumption. 
             apply intern_incr_as_inj; trivial.
             apply sm_inject_separated_mem; eassumption.
    red; intros bb fbb Hbb. destruct (GFP _ _ Hbb).
          split; trivial.
          eapply intern_incr_as_inj; eassumption.    
    assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply A.
          rewrite <- FRG. eapply (Glob _ H0).
    eapply BuiltinEffect_Propagate' with 
      (vargs := args)
      (tvargs := args'); eauto.
    econstructor; eauto. rewrite <-restrict_sm_all; auto.
    eapply BuiltinEffect_Propagate' with 
      (vargs := args)
      (tvargs := args'); eauto.
    econstructor; eauto. rewrite <-restrict_sm_all; auto. }

{ (* return *)
  inv STACKS. simpl in *.
  destruct PRE as [RC [PG [GFP [Glob [SMV WD]]]]].
  eexists; eexists; eexists; split.
    right. split. omega. eapply effstep_star_zero.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      intuition. 
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
      apply extensionality; intros; rewrite (freshloc_irrefl). intuition.
  split. 2: intuition.
  split; intuition.  
  destruct (GFP _ _ H5).
  econstructor; eauto.
    { inv H6. inv ATPC.
      rewrite restrict_sm_all in H12.
      destruct (restrictD_Some _ _ _ _ _ H12); clear H12. 
      rewrite H6 in H; inv H.
      rewrite Int.add_zero.
      econstructor; eassumption. }
    congruence.
    rewrite restrict_sm_zero_or_localid in H7; trivial. } 
Qed.

(** The simulation proof *)
Theorem transl_program_correct:
  forall (R: list_norepet (map fst (prog_defs prog)))
         (init_mem: exists m0, Genv.init_mem prog = Some m0),
  SM_simulation.SM_simulation_inject 
   (Mach_eff_sem hf return_address_offset) (Asm_eff_sem hf) ge tge.
Proof.
intros.
assert (GDE:= GDE_lemma). 
 eapply effect_simulations_lemmas.inj_simulation_plus with
  (match_states:=MATCH) (measure:=measure).
(*genvs_dom_eq*)
  assumption.
(*MATCH_wd*)
  apply MATCH_wd. 
(*MATCH_reachclosed*)
  apply MATCH_RC.
(*MATCH_restrict*)
  apply MATCH_restrict.
(*MATCH_valid*)
  apply MATCH_valid.
(*MATCH_preserves_globals*)
  apply MATCH_PG.
(* init*) { intros.
    eapply (MATCH_initial _ _ _); eauto.
    destruct init_mem as [m0 INIT].
    exists m0; split; auto.
    unfold meminj_preserves_globals in H2.    
    destruct H2 as [A [B C]].

    assert (P: forall p q, {Ple p q} + {Plt q p}).
      intros p q.
      case_eq (Pos.leb p q).
      intros TRUE.
      apply Pos.leb_le in TRUE.
      left; auto.
      intros FALSE.
      apply Pos.leb_gt in FALSE.
      right; auto.

    cut (forall b, Plt b (Mem.nextblock m0) -> 
           exists id, Genv.find_symbol ge id = Some b). intro D.
    
    split.
    destruct (P (Mem.nextblock m0) (Mem.nextblock m1)); auto.
    exfalso. 
    destruct (D _ p).
    apply A in H2.
    assert (Mem.valid_block m1 (Mem.nextblock m1)).
      eapply Mem.valid_block_inject_1; eauto.
    clear - H7; unfold Mem.valid_block in H7.
    xomega.

    destruct (P (Mem.nextblock m0) (Mem.nextblock m2)); auto.
    exfalso. 
    destruct (D _ p).
    apply A in H2.
    assert (Mem.valid_block m2 (Mem.nextblock m2)).
      eapply Mem.valid_block_inject_2; eauto.
    clear - H7; unfold Mem.valid_block in H7.
    xomega.
    
    intros b LT.    
    unfold ge. 
    apply valid_init_is_global with (b0 := b) in INIT.
    eapply INIT; auto.
    apply R.
    apply LT. } 
{ (* halted *)
    intros. destruct H as [MC [RC [PG [Glob [VAL [WD INJ]]]]]].
    inv MC; try solve[inv H0]. simpl in H0.
    destruct s; simpl; try solve[congruence]. 
    destruct retty0; inv H0.
    { inv AG. rewrite restrict_sm_all in agree_mregs.
    simpl in ATPC. inv ATPC. simpl.
    destruct t. 
    + simpl in H1. inv H1. exists (rs (preg_of AX)); split; auto.
    + simpl in H1. inv H1. exists (rs (preg_of FP0)); split; auto.
    + simpl in H1. inv H1. 
      case_eq (decode_longs (Tlong::nil) ((rs(preg_of DX))::(rs(preg_of AX))::nil)).
      simpl. inversion 1. simpl. inversion 1. subst.
      exists (Val.longofwords (rs EDX) (rs EAX)). 
      split; auto.
      split; auto.
      apply val_longofwords_inject; apply agree_mregs.
    + simpl in H1. inv H1. exists (rs (preg_of FP0)); split; auto. }
    { inv AG. rewrite restrict_sm_all in agree_mregs.
    simpl in ATPC. inv ATPC. simpl.
    exists (rs (preg_of AX)); split; auto. } }
{ (*at_external *) apply MATCH_atExternal. }
{ (*after_external *) apply MATCH_afterExternal. trivial. }
{ (*effcore_diagram *)
  intros.
   exploit MATCH_effcore_diagram; try eassumption.
    intros [st2' [m2' [U2 [CSTgt [mu' MU]]]]].
    exists st2', m2', mu'.
    split. eapply MU.
    split. eapply MU.
    split. eapply MU.
    split. eapply MU. 
    exists U2. split. trivial. eapply MU. }
Qed.

End PRESERVATION.
