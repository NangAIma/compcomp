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

(** Correctness proof for clean-up of labels *)

Require Import Coqlib.
Require Import Ordered.
Require Import FSets.
Require Import AST.
Require Import Integers.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Op.
Require Import Locations.
Require Import Linear.
Require Import CleanupLabels.

Require Import mem_lemmas.
Require Import core_semantics.
Require Import core_semantics_lemmas.
Require Import reach.
Require Import effect_semantics.
Require Import StructuredInjections.
Require Import effect_simulations.
Require Import effect_properties.
Require Import effect_simulations_lemmas.

Require Export Axioms.
Require Import Linear_coop.
Require Import BuiltinEffects.
Require Import Linear_eff.
Require Import OpEFF.

Module LabelsetFacts := FSetFacts.Facts(Labelset).

Section CLEANUP.

Variable prog: program.
Let tprog := transf_program prog.
Let ge := Genv.globalenv prog.
Let tge := Genv.globalenv tprog.

Lemma symbols_preserved:
  forall (s: ident), Genv.find_symbol tge s = Genv.find_symbol ge s.
Proof.
  intros; unfold ge, tge, tprog, transf_program. 
  apply Genv.find_symbol_transf.
Qed.

Lemma varinfo_preserved:
  forall b, Genv.find_var_info tge b = Genv.find_var_info ge b.
Proof.
  intros; unfold ge, tge, tprog, transf_program. 
  apply Genv.find_var_info_transf.
Qed.

Lemma functions_translated:
  forall (v: val) (f: fundef),
  Genv.find_funct ge v = Some f ->
  Genv.find_funct tge v = Some (transf_fundef f).
Proof.  
  intros.
  exact (Genv.find_funct_transf transf_fundef _ _ H).
Qed.

Lemma function_ptr_translated:
  forall (b: block) (f: fundef),
  Genv.find_funct_ptr ge b = Some f ->
  Genv.find_funct_ptr tge b = Some (transf_fundef f).
Proof.  
  intros. 
  exact (Genv.find_funct_ptr_transf transf_fundef _ _ H).
Qed.

Lemma sig_function_translated:
  forall f,
  funsig (transf_fundef f) = funsig f.
Proof.
  intros. destruct f; reflexivity.
Qed.

Lemma find_function_translated:
  forall ros ls f,
  find_function ge ros ls = Some f ->
  find_function tge ros ls = Some (transf_fundef f).
Proof.
  unfold find_function; intros; destruct ros; simpl.
  apply functions_translated; auto.
  rewrite symbols_preserved. destruct (Genv.find_symbol ge i).
  apply function_ptr_translated; auto.
  congruence.
Qed.

(*NEW, GFP as in selectionproofEFF*)
Definition globalfunction_ptr_inject (j:meminj):=
  forall b f, Genv.find_funct_ptr ge b = Some f -> 
              j b = Some(b,0) /\ isGlobalBlock ge b = true.  

Lemma restrict_preserves_globalfun_ptr: forall j X
  (PG : globalfunction_ptr_inject j)
  (Glob : forall b, isGlobalBlock ge b = true -> X b = true),
globalfunction_ptr_inject (restrict j X).
Proof. intros.
  red; intros. 
  destruct (PG _ _ H). split; trivial.
  apply restrictI_Some; try eassumption.
  apply (Glob _ H1).
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
     split; intros; destruct H as [id Hid].
      rewrite <- varinfo_preserved in Hid.
      exists id; assumption.
     rewrite varinfo_preserved in Hid.
      exists id; assumption.
Qed.

Lemma restrict_GFP_vis: forall mu
  (GFP : globalfunction_ptr_inject (as_inj mu))
  (Glob : forall b, isGlobalBlock ge b = true -> 
                    frgnBlocksSrc mu b = true),
  globalfunction_ptr_inject (restrict (as_inj mu) (vis mu)).
Proof. intros.
  unfold vis. 
  eapply restrict_preserves_globalfun_ptr. eassumption.
  intuition.
Qed.

(*From Cminorgenproof*)
Remark val_inject_function_pointer:
  forall v fd j tv,
  Genv.find_funct ge v = Some fd ->
  globalfunction_ptr_inject j ->
  val_inject j v tv ->
  tv = v.
Proof.
  intros. exploit Genv.find_funct_inv; eauto. intros [b EQ]. subst v.
  inv H1.
  rewrite Genv.find_funct_find_funct_ptr in H.
  destruct (H0 _ _ H).
  rewrite H1 in H4; inv H4.
  rewrite Int.add_zero. trivial.
Qed.

(** Correctness of [labels_branched_to]. *)

Definition instr_branches_to (i: instruction) (lbl: label) : Prop :=
  match i with
  | Lgoto lbl' => lbl = lbl'
  | Lcond cond args lbl' => lbl = lbl'
  | Ljumptable arg tbl => In lbl tbl
  | _ => False
  end.

Remark add_label_branched_to_incr:
  forall ls i, Labelset.Subset ls (add_label_branched_to ls i).
Proof.
  intros; red; intros; destruct i; simpl; auto.
  apply Labelset.add_2; auto.
  apply Labelset.add_2; auto.
  revert H; induction l; simpl. auto. intros; apply Labelset.add_2; auto.
Qed.

Remark add_label_branched_to_contains:
  forall ls i lbl,
  instr_branches_to i lbl ->
  Labelset.In lbl (add_label_branched_to ls i).
Proof.
  destruct i; simpl; intros; try contradiction.
  apply Labelset.add_1; auto.
  apply Labelset.add_1; auto.
  revert H. induction l; simpl; intros. 
  contradiction.
  destruct H. apply Labelset.add_1; auto. apply Labelset.add_2; auto.
Qed.

Lemma labels_branched_to_correct:
  forall c i lbl,
  In i c -> instr_branches_to i lbl -> Labelset.In lbl (labels_branched_to c).
Proof.
  intros.
  assert (forall c' bto,
             Labelset.Subset bto (fold_left add_label_branched_to c' bto)).
  induction c'; intros; simpl; red; intros.
  auto.
  apply IHc'. apply add_label_branched_to_incr; auto.

  assert (forall c' bto,
             In i c' -> Labelset.In lbl (fold_left add_label_branched_to c' bto)).
  induction c'; simpl; intros.
  contradiction.
  destruct H2.   
  subst a. apply H1. apply add_label_branched_to_contains; auto. 
  apply IHc'; auto.

  unfold labels_branched_to. auto.
Qed.

(** Commutation with [find_label]. *)

Lemma remove_unused_labels_cons:
  forall bto i c,
  remove_unused_labels bto (i :: c) = 
  match i with
  | Llabel lbl =>
      if Labelset.mem lbl bto then i :: remove_unused_labels bto c else remove_unused_labels bto c
  | _ =>
      i :: remove_unused_labels bto c
  end.
Proof.
  unfold remove_unused_labels; intros. rewrite list_fold_right_eq. auto. 
Qed.


Lemma find_label_commut:
  forall lbl bto,
  Labelset.In lbl bto ->
  forall c c',
  find_label lbl c = Some c' ->
  find_label lbl (remove_unused_labels bto c) = Some (remove_unused_labels bto c').
Proof.
  induction c; simpl; intros.
  congruence.
  rewrite remove_unused_labels_cons.
  unfold is_label in H0. destruct a; simpl; auto.
  destruct (peq lbl l). subst l. inv H0.
  rewrite Labelset.mem_1; auto. 
  simpl. rewrite peq_true. auto.
  destruct (Labelset.mem l bto); auto. simpl. rewrite peq_false; auto. 
Qed.

Corollary find_label_translated:
  forall f i c' lbl c,
  incl (i :: c') (fn_code f) ->
  find_label lbl (fn_code f) = Some c ->
  instr_branches_to i lbl ->
  find_label lbl (fn_code (transf_function f)) =
     Some (remove_unused_labels (labels_branched_to (fn_code f)) c).
Proof.
  intros. unfold transf_function; unfold cleanup_labels; simpl. 
  apply find_label_commut. eapply labels_branched_to_correct; eauto. 
  apply H; auto with coqlib.
  auto.
Qed.

Lemma find_label_incl:
  forall lbl c c', find_label lbl c = Some c' -> incl c' c.
Proof.
  induction c; simpl; intros.
  discriminate.
  destruct (is_label lbl a). inv H; auto with coqlib. auto with coqlib.
Qed.

(********** Lenb: new, but similar to what's there in linearize **)

Definition agree_regs (j: meminj) (ls1 ls2: Linear.locset): Prop :=
  (forall r, val_inject j (ls1 (R r)) (ls2 (R r))) /\
  forall sl ofs ty, val_inject j (ls1 (S sl ofs ty)) (ls2 (S sl ofs ty)).

Lemma agree_regs_incr j k ls1 ls2: 
  agree_regs j ls1 ls2 -> inject_incr j k ->
  agree_regs k ls1 ls2.
Proof. intros. destruct H. split; intros.
  eapply val_inject_incr; eauto.
  eapply val_inject_incr; eauto.
Qed.

Lemma agree_find_function_translated:
  forall j ros ls1 ls2 f,
  meminj_preserves_globals ge j ->
  globalfunction_ptr_inject j ->
  agree_regs j ls1 ls2 ->
  find_function ge ros ls1 = Some f ->
  find_function tge ros ls2 = Some (transf_fundef f).
Proof.
  unfold find_function; intros; destruct ros; simpl.
  apply functions_translated.
    destruct (Genv.find_funct_inv _ _ H2) as [b Hb].
    destruct H1 as [H1 _].
    specialize (H1 m). rewrite Hb in *. inv H1.
    rewrite Genv.find_funct_find_funct_ptr in H2.
    destruct (H0 _ _ H2).
    rewrite H1 in H6. inv H6.
    rewrite Int.add_zero. assumption.
  rewrite symbols_preserved. destruct (Genv.find_symbol ge i).
  apply function_ptr_translated; auto.
  congruence.
Qed.

Lemma agree_regs_set:
  forall j ls1 ls2 r v v',
  agree_regs j ls1 ls2 ->
  val_inject j v v' ->
  agree_regs j (Locmap.set (R r) v ls1) (Locmap.set (R r) v' ls2).
Proof.
  intros. destruct H; split; intros.
  destruct (mreg_eq r r0).
    subst.  
    repeat rewrite Locmap.gss; trivial.
  repeat rewrite Locmap.gso. auto. red. auto. red. auto.

  repeat rewrite Locmap.gso; auto. red. auto. red. auto.
Qed.

Lemma agree_regs_list j ls1 ls2: forall 
      (AG: agree_regs  j ls1 ls2) args,
      val_list_inject j (LTL.reglist ls1 args) (LTL.reglist ls2 args).
Proof. intros. destruct AG.
  induction args; econstructor; eauto.
Qed.

Lemma agree_regs_undef j: forall rl ls1 ls2 
        (AG: agree_regs j ls1 ls2),
     agree_regs j (LTL.undef_regs rl ls1) (LTL.undef_regs rl ls2).
Proof. intros rl.
  induction rl; simpl; intros.
  auto.
  apply agree_regs_set; auto.
Qed. 

Lemma agree_regs_return j: forall ls1 ls2 pls1 pls2
        (AG: agree_regs j ls1 ls2) 
        (parentsAGREE : agree_regs j pls1 pls2),
      agree_regs j (LTL.return_regs pls1 ls1) (LTL.return_regs pls2 ls2).
Proof. intros.
red; intros. 
split; intros.
  unfold LTL.return_regs.
  destruct (in_dec mreg_eq r Conventions1.destroyed_at_call).
  eapply AG. eapply parentsAGREE.
unfold LTL.return_regs.
  eapply parentsAGREE.
Qed.

Lemma agree_regs_call_regs j ls1 ls2 :
  agree_regs j ls1 ls2 ->
  agree_regs j (LTL.call_regs ls1) (LTL.call_regs ls2).
Proof.
  intros.
  destruct H; split; intros; eauto.
  unfold LTL.call_regs; simpl. 
  destruct sl; try constructor. eapply H0. 
Qed.

Lemma agree_regs_set_regs:
  forall j rl vl vl' ls1 ls2,
  agree_regs j ls1 ls2 ->
  val_list_inject j vl vl' ->
  agree_regs j (Locmap.setlist (map R rl) vl ls1) (Locmap.setlist (map R rl) vl' ls2).
Proof.
  induction rl; simpl; intros. 
  auto.
  inv H0. auto.
  apply IHrl; auto. apply agree_regs_set; auto. 
Qed.

Definition slots_outgoing L: Prop :=
  forall l, In l L -> match l with 
                        R r => True 
                      | S sl pos ty => match sl with Outgoing => True | _ => False end
                      end.
  

Lemma agree_regs_map_outgoing j ls1 ls2: forall 
      (AG: agree_regs  j ls1 ls2) f
      (HF: slots_outgoing f),
      val_list_inject j (map ls1 f) (map ls2 f).
Proof. intros AG f.
  induction f; econstructor; eauto.
    clear IHf.
    destruct a. apply AG.
    exploit (HF (S sl pos ty)); clear HF. left; trivial.
    intros. destruct sl; inv H.
    eapply AG.     
  eapply IHf. red; intros. eapply HF. right. trivial.
Qed.

Lemma agree_regs_setstack j rs ls2 sl ofs ty src:
        agree_regs j rs ls2 ->
      agree_regs j
                 (Locmap.set (S sl ofs ty) (rs (R src))
                             (LTL.undef_regs (destroyed_by_setstack ty) rs))
                 (Locmap.set (S sl ofs ty) (ls2 (R src))
                             (LTL.undef_regs (destroyed_by_setstack ty) ls2)).
Proof. intros AGREE.
    split; intros.
      repeat rewrite Locmap.gso. 
      apply (agree_regs_undef _ (destroyed_by_setstack ty)). apply AGREE. 
        red; trivial. red; trivial. 
    unfold Locmap.set.
    remember (Loc.eq (S sl ofs ty) (S sl0 ofs0 ty0)) as w.
    destruct w. clear Heqw.  apply eq_sym in e. inv e.
       eapply val_load_result_inject. eapply AGREE.
    destruct (Loc.diff_dec (S sl ofs ty) (S sl0 ofs0 ty0)). 
        apply (agree_regs_undef _ (destroyed_by_setstack ty)). apply AGREE.
        constructor.
Qed.

Lemma agree_regs_setlist j:
  forall l ls1 ls2 v v',
  agree_regs j ls1 ls2 ->
  val_list_inject j v v' ->
  slots_outgoing l ->
  agree_regs j (Locmap.setlist l v ls1) (Locmap.setlist l v' ls2).
Proof.
  induction l; simpl; intros; trivial.
  inv H0. auto.
  apply IHl; auto.
     clear IHl.
     destruct a. apply agree_regs_set; auto.
  split; intros.
    repeat rewrite Locmap.gso. eapply H. red. auto. red. auto.
  unfold Locmap.set.
    remember (Loc.eq (S sl pos ty) (S sl0 ofs ty0)) as w.
    destruct w. clear Heqw.  apply eq_sym in e. inv e.
       eapply val_load_result_inject. eapply H2.
    destruct (Loc.diff_dec (S sl pos ty) (S sl0 ofs ty0)). 
        apply H.
        constructor.
   red; intros. eapply H1. right; trivial.
Qed.

(***********************************************************************)

(*NEW, as in Linearize*) 
Definition sp_mapped mu sp1 sp2:=
  val_inject (local_of mu) sp1 sp2 /\
  (forall b z, sp1 = Vptr b z -> exists b', as_inj mu b = Some(b',0)).
 
Lemma sp_mapped_intern_incr mu mu' sp1 sp2: 
       sp_mapped mu sp1 sp2 -> intern_incr mu mu' -> SM_wd mu' ->
       sp_mapped mu' sp1 sp2.
Proof. intros.
  destruct H. split; intros.
    eapply val_inject_incr; try eassumption.
    eapply H0.
  destruct (H2 _ _ H3).
  exists x; eapply intern_incr_as_inj; try eassumption.
Qed.

Lemma sp_mapped_extern_incr mu mu' sp1 sp2: 
       sp_mapped mu sp1 sp2 -> extern_incr mu mu' -> SM_wd mu' ->
       sp_mapped mu' sp1 sp2.
Proof. intros.
  destruct H. split; intros.
    eapply val_inject_incr; try eassumption.
      assert (local_of mu = local_of mu') by eapply H0.
      rewrite H3; apply inject_incr_refl.
  destruct (H2 _ _ H3).
  exists x; eapply extern_incr_as_inj; try eassumption.
Qed.

(*****************************************************************)


(** Correctness of clean-up *)

Inductive match_stackframes mu: stackframe -> stackframe -> Prop :=
  | match_stackframe_intro:
      forall f sp ls c (*NEW:*) tsp tls
      (*NEW*) (REGS: agree_regs (restrict (as_inj mu) (vis mu)) ls tls)
      (*NEW*) (SPmapped: sp_mapped mu sp tsp),
      incl c f.(fn_code) ->
      match_stackframes mu
        (Stackframe f sp ls c)
        (Stackframe (transf_function f) tsp tls 
          (remove_unused_labels (labels_branched_to f.(fn_code)) c)).

Lemma match_stackframes_intern_incr mu mu' s ts:
     match_stackframes mu s ts ->
     intern_incr mu mu' -> SM_wd mu' ->
     match_stackframes mu' s ts.
Proof. intros. inv H; econstructor; eauto.
  eapply agree_regs_incr; try eassumption.
    eapply intern_incr_restrict; try eassumption.
    eapply sp_mapped_intern_incr; eassumption.
Qed.

Lemma list_match_stackframes_intern_incr mu mu': forall s ts,
     list_forall2 (match_stackframes mu) s ts ->
     intern_incr mu mu' -> SM_wd mu' ->
     list_forall2 (match_stackframes mu') s ts.
Proof. intros.
  induction H; econstructor; eauto.
  eapply match_stackframes_intern_incr; eassumption.
Qed.

Lemma match_stackframes_extern_incr mu mu' s ts:
     match_stackframes mu s ts ->
     extern_incr mu mu' -> SM_wd mu' ->
     match_stackframes mu' s ts.
Proof. intros. inv H; econstructor; eauto.
  eapply agree_regs_incr; try eassumption.
    eapply extern_incr_restrict; try eassumption.
    eapply sp_mapped_extern_incr; eassumption.
Qed.

Lemma list_match_stackframes_extern_incr mu mu': forall s ts,
     list_forall2 (match_stackframes mu) s ts ->
     extern_incr mu mu' -> SM_wd mu' ->
     list_forall2 (match_stackframes mu') s ts.
Proof. intros.
  induction H; econstructor; eauto.
  eapply match_stackframes_extern_incr; eassumption.
Qed.

Inductive match_states mu: Linear_core -> mem -> Linear_core -> mem -> Prop :=
  | match_states_intro:
      forall s f sp c ls m ts (*NEW*) tsp tls tm
        (STACKS: list_forall2 (match_stackframes mu) s ts)
        (INCL: incl c f.(fn_code))
        (*NEW*) (AGREE: agree_regs (restrict (as_inj mu) (vis mu)) ls tls)
        (*NEW*) (SPlocal: sp_mapped mu sp tsp),
      match_states mu (Linear_State s f sp c ls) m
                      (Linear_State ts (transf_function f) tsp 
                        (remove_unused_labels (labels_branched_to f.(fn_code)) c) tls) tm
  | match_states_call:
      forall s f ls m ts (*NEW*) tls tm
      (*NEW*) (AGREE: agree_regs (restrict (as_inj mu) (vis mu)) ls tls),
      list_forall2 (match_stackframes mu) s ts ->
      match_states mu (Linear_Callstate s f ls) m
                      (Linear_Callstate ts (transf_fundef f) tls) tm
  | match_states_return:
      forall s ls m ts (*NEW*) tpopt tls tm
     (*NEW*) (AGREE: agree_regs (restrict (as_inj mu) (vis mu)) ls tls),
      list_forall2 (match_stackframes mu) s ts ->
      match_states mu (Linear_Returnstate s tpopt ls) m
                      (Linear_Returnstate ts tpopt tls) tm.

(*Lenb: converted to Linear_core*)
Definition measure (st: Linear_core) : nat :=
  match st with
  | Linear_State s f sp c ls => List.length c
  | _ => O
  end.

Definition lt_state (S1 S2: Linear_core) :=
  lt (measure S1) (measure S2).

Require Import Wellfounded.
Lemma lt_state_wf:
  well_founded lt_state.
Proof. unfold lt_state. apply wf_inverse_image with (f := measure).
    apply lt_wf. 
Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Definition MATCH mu c1 m1 c2 m2:Prop :=
  match_states (restrict_sm mu (vis mu)) c1 m1 c2 m2 /\
  REACH_closed m1 (vis mu) /\
  meminj_preserves_globals ge (as_inj mu) /\
  globalfunction_ptr_inject (as_inj mu) /\
  (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true) /\
  sm_valid mu m1 m2 /\ SM_wd mu /\ Mem.inject (as_inj mu) m1 m2.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma MATCH_wd: forall mu c1 m1 c2 m2 
  (MC: MATCH mu c1 m1 c2 m2), SM_wd mu.
Proof. intros. eapply MC. Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma MATCH_RC: forall mu c1 m1 c2 m2 
  (MC: MATCH mu c1 m1 c2 m2), REACH_closed m1 (vis mu).
Proof. intros. eapply MC. Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma MATCH_restrict: forall mu c1 m1 c2 m2 X
  (MC: MATCH mu c1 m1 c2 m2)
  (HX: forall b : block, vis mu b = true -> X b = true) 
  (RX: REACH_closed m1 X), 
  MATCH (restrict_sm mu X) c1 m1 c2 m2.
Proof. intros.
  destruct MC as [MS [RC [PG [GFP [Glob [SMV [WD INJ]]]]]]].
assert (WDR: SM_wd (restrict_sm mu X)).
   apply restrict_sm_WD; assumption.
split.
  rewrite vis_restrict_sm.
  rewrite restrict_sm_nest; intuition.
split. unfold vis.
  rewrite restrict_sm_locBlocksSrc, restrict_sm_frgnBlocksSrc.
  apply RC.
split. clear -PG Glob HX.
  eapply restrict_sm_preserves_globals; try eassumption.
  unfold vis in HX. intuition.
split. rewrite restrict_sm_all.
  eapply restrict_preserves_globalfun_ptr; try eassumption.
  unfold vis in HX. intuition.
split. 
  rewrite restrict_sm_frgnBlocksSrc. apply Glob.
split. 
  destruct SMV.
  split; intros.
    rewrite restrict_sm_DOM in H1.
    apply (H _ H1).
  rewrite restrict_sm_RNG in H1.
    apply (H0 _ H1).
split. assumption.
  rewrite restrict_sm_all.
  eapply inject_restrict; eassumption.
Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma MATCH_valid: forall mu c1 m1 c2 m2 
  (MC: MATCH mu c1 m1 c2 m2), sm_valid mu m1 m2.
Proof. intros. eapply MC. Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma MATCH_PG: forall mu c1 m1 c2 m2 
  (MC: MATCH mu c1 m1 c2 m2),
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

(*Lenb: as in LinearizeproofEFF.v*)
Lemma replace_locals_stackframes mu pubSrc' pubTgt': forall a b,
      match_stackframes (restrict_sm mu (vis mu)) a b->
      match_stackframes (restrict_sm (replace_locals mu pubSrc' pubTgt') (vis mu)) a b.
Proof. intros.
induction H; econstructor; eauto.
  rewrite restrict_sm_all, vis_restrict_sm, replace_locals_vis,
          replace_locals_as_inj, restrict_nest. 
  rewrite restrict_sm_all, vis_restrict_sm, restrict_nest in REGS. trivial.
  trivial. trivial.
  destruct SPmapped.
  split; intros.
    rewrite restrict_sm_local, replace_locals_local.
    rewrite restrict_sm_local in H0. trivial. 
  subst. rewrite restrict_sm_all, replace_locals_as_inj in *.
    eapply H1. reflexivity.
Qed.

(*Lenb: as in LinearizeproofEFF.v*)
Lemma replace_locals_forall_stackframes mu pubSrc' pubTgt': forall s ts,
      list_forall2 (match_stackframes (restrict_sm mu (vis mu))) s ts ->
      list_forall2 (match_stackframes (restrict_sm (replace_locals mu pubSrc' pubTgt') (vis mu))) s ts.
Proof. intros.
induction H; econstructor; eauto. clear IHlist_forall2.
eapply replace_locals_stackframes; eassumption.
Qed.

(*WAS:
Lemma match_parent_locset:
  forall s ts,
  list_forall2 match_stackframes s ts ->
  parent_locset ts = parent_locset s.
Proof.
  induction 1; simpl. auto. inv H; auto.
Qed.
*)

Lemma match_parent_locset mu:
  forall s ts,
  list_forall2 (match_stackframes mu) s ts ->
  agree_regs (restrict (as_inj mu) (vis mu))
             (parent_locset s) (parent_locset ts).
Proof.
  induction 1; simpl.
    red; intros. split; intros. econstructor.  econstructor.
    inv H; trivial.
Qed.

Lemma MATCH_atExternal: forall mu c1 m1 c2 m2 e vals1 ef_sig
       (MTCH: MATCH mu c1 m1 c2 m2)
       (AtExtSrc: at_external Linear_eff_sem c1 = Some (e, ef_sig, vals1)),
     Mem.inject (as_inj mu) m1 m2 /\
     exists vals2,
       Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2 /\
       at_external Linear_eff_sem c2 = Some (e, ef_sig, vals2) /\
      (forall pubSrc' pubTgt',
       pubSrc' = (fun b => locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b) ->
       pubTgt' = (fun b : block => locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b) ->
       forall nu : SM_Injection, nu = replace_locals mu pubSrc' pubTgt' ->
       MATCH nu c1 m1 c2 m2 /\ Mem.inject (shared_of nu) m1 m2).
Proof. intros. 
destruct MTCH as [MC [RC [PG [GFP [Glob [SMV [WD INJ]]]]]]].
inv MC; simpl in AtExtSrc; inv AtExtSrc.
destruct f; simpl in *; inv H1.
split; trivial. 
assert (ValsInj: Forall2 (val_inject (restrict (as_inj mu) (vis mu)))
  (decode_longs (sig_args (ef_sig e)) (map ls (Conventions1.loc_arguments (ef_sig e))))
  (decode_longs (sig_args (ef_sig e)) (map tls (Conventions1.loc_arguments (ef_sig e))))).
{ rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  eapply val_list_inject_forall_inject.
  apply decode_longs_inject.
  eapply agree_regs_map_outgoing; trivial.
    red; intros. apply Conventions1.loc_arguments_rec_charact in H0. 
           destruct l; try contradiction.
           destruct sl; try contradiction. trivial. }
eexists. split. eassumption.
specialize (forall_vals_inject_restrictD _ _ _ _ ValsInj); intros.
exploit replace_locals_wd_AtExternal; try eassumption. 
intuition. 
(*MATCH*)
    split; subst; rewrite replace_locals_vis. 
      econstructor; repeat rewrite restrict_sm_all, vis_restrict_sm, replace_locals_vis, replace_locals_as_inj in *; eauto.
      eapply replace_locals_forall_stackframes; eassumption.
    subst. rewrite restrict_sm_all, vis_restrict_sm, replace_locals_frgnBlocksSrc, replace_locals_as_inj in *.
           intuition.
   (*sm_valid*)
     red. rewrite replace_locals_DOM, replace_locals_RNG. apply SMV.
(*Shared*)
  eapply inject_shared_replace_locals; try eassumption.
  subst; trivial.
Qed.

Lemma match_stackframes_restrict_sm mu X s ts: forall
     (MS: match_stackframes mu s ts)
     (HX: forall b : block, vis mu b = true -> X b = true)
     (WD: SM_wd mu),
     match_stackframes (restrict_sm mu X) s ts.
Proof. intros.
  inv MS; econstructor; eauto.
    rewrite restrict_sm_all, vis_restrict_sm.
    rewrite restrict_nest; trivial.
  destruct SPmapped; split.
    rewrite restrict_sm_local. eapply val_inject_incr; try eassumption.
      red; intros. eapply restrictI_Some; try eassumption.
      apply HX. unfold vis. destruct (local_DomRng _ WD _ _ _ H2).
      rewrite H3; trivial.
    rewrite restrict_sm_all. intros; subst.
      destruct (H1 _ _ (eq_refl _)) as [? ?]; clear H1.
      inv H0. 
      eexists. eapply restrictI_Some; try eassumption.
      rewrite (local_in_all _ WD _ _ _ H4) in H2. inv H2.
      apply HX. unfold vis. destruct (local_DomRng _ WD _ _ _ H4).
      rewrite H0; trivial.
Qed.

Lemma match_stackframes_forall_restrict_sm mu X s ts: forall
      (H: list_forall2 (match_stackframes mu) s ts)
      (HX: forall b : block, vis mu b = true -> X b = true)
      (WD: SM_wd mu),
     list_forall2 (match_stackframes (restrict_sm mu X)) s ts.
Proof. intros.
  induction H; econstructor; eauto.
  eapply match_stackframes_restrict_sm; eauto.
Qed.

Lemma match_stackframes_replace_externs mu FS FT s ts: forall
     (MS: match_stackframes mu s ts)
     (HFS: forall b, vis mu b = true -> 
          locBlocksSrc mu b || FS b = true),
     match_stackframes (replace_externs mu FS FT) s ts.
Proof. intros MS HFS. inv MS; econstructor; eauto.
  eapply agree_regs_incr; try eassumption.
    rewrite replace_externs_as_inj, replace_externs_vis.
    red; intros. destruct (restrictD_Some _ _ _ _ _ H0).
      apply HFS in H2. 
      apply restrictI_Some; trivial.
    destruct SPmapped; split; intros. 
     rewrite replace_externs_local; trivial. 
     rewrite replace_externs_as_inj; eauto. 
Qed.

Lemma match_stackframes_forall_replace_externs mu FS FT s ts:
      list_forall2 (match_stackframes mu) s ts ->
     (forall b, vis mu b = true -> locBlocksSrc mu b || FS b = true) ->
     list_forall2 (match_stackframes (replace_externs mu FS FT)) s ts.
Proof. intros.
  induction H; econstructor; eauto.
  eapply match_stackframes_replace_externs; eauto.
Qed.

Lemma match_stackframes_replace_locals mu PS PT s ts: forall
      (MS: match_stackframes mu s ts),
      match_stackframes (replace_locals mu PS PT) s ts.
Proof. intros. inv MS; econstructor; eauto.
  rewrite replace_locals_as_inj, replace_locals_vis. trivial.
  destruct SPmapped; split; intros. 
     rewrite replace_locals_local; trivial. 
     rewrite replace_locals_as_inj; eauto. 
Qed.

Lemma match_stackframes_forall_replace_locals mu PS PT s ts: forall
      (MS: list_forall2 (match_stackframes mu) s ts),
      list_forall2 (match_stackframes (replace_locals mu PS PT)) s ts.
Proof. intros.
  induction MS; econstructor; eauto.
  eapply match_stackframes_replace_locals; eauto.
Qed.

Lemma match_stackframes_forall_extern_incr mu nu s ts: forall
      (MS: list_forall2 (match_stackframes mu) s ts)
      (EXT: extern_incr mu nu) (WDnu: SM_wd nu),
      list_forall2 (match_stackframes nu) s ts.
Proof. intros.
  induction MS; econstructor; eauto.
  eapply match_stackframes_extern_incr; eauto.
Qed.

Lemma match_stackframes_restrict_sm_incr mu nu X Y s ts: forall
     (MS: match_stackframes (restrict_sm mu X) s ts)
     (INC: inject_incr (as_inj mu) (as_inj nu))
     (HX: forall b, vis mu b = true -> X b = true)
     (HY: forall b, vis nu b = true -> Y b = true)
     (H_mu_nu: forall b, vis mu b = true -> vis nu b = true)
     (HXY: inject_incr (restrict (local_of mu) X) (restrict (local_of nu) Y)),
     match_stackframes (restrict_sm nu Y) s ts.
Proof. intros.
  inv MS; econstructor; eauto.
    rewrite restrict_sm_all, vis_restrict_sm.
    rewrite restrict_sm_all, vis_restrict_sm in REGS.
    eapply agree_regs_incr; try eassumption.
    rewrite restrict_nest; trivial.
    rewrite restrict_nest; trivial.
      red; intros b tb delta Hb.
         destruct (restrictD_Some _ _ _ _ _ Hb).
         eapply restrictI_Some. apply INC; eassumption.
         apply H_mu_nu. trivial.
  destruct SPmapped; split.
    rewrite restrict_sm_local in *. eapply val_inject_incr; try eassumption.
    rewrite restrict_sm_all in *. intros; subst.
      destruct (H1 _ _ (eq_refl _)) as [? ?]; clear H1.
      inv H0. 
      eexists. eapply restrictI_Some.
        eapply INC. eapply restrictD_Some. eassumption.
      rewrite restrict_sm_local in H4.
      specialize (HXY _ _ _ H4). 
      eapply (restrictD_Some _ _ _ _ _ HXY).
Qed.

Lemma match_stackframes_forall_restrict_sm_incr mu nu X Y s ts: forall
     (MS: list_forall2 (match_stackframes (restrict_sm mu X)) s ts)
     (INC: inject_incr (as_inj mu) (as_inj nu))
     (HX: forall b, vis mu b = true -> X b = true)
     (HY: forall b, vis nu b = true -> Y b = true)
     (H_mu_nu: forall b, vis mu b = true -> vis nu b = true)
     (HXY: inject_incr (restrict (local_of mu) X) (restrict (local_of nu) Y)),
     list_forall2 (match_stackframes (restrict_sm nu Y)) s ts.
Proof. intros.
  induction MS; econstructor; eauto.
  eapply match_stackframes_restrict_sm_incr; eauto.
Qed.

Lemma map_R_outgoing: forall l, slots_outgoing (map R l).
Proof. red. intros.
induction l; simpl in *. contradiction.
  destruct H; subst. trivial.
  apply (IHl H).
Qed.

Lemma MATCH_afterExternal: forall
      (GDE : genvs_domain_eq ge tge)
      mu st1 st2 m1 e vals1 m2 ef_sig vals2 e' ef_sig'
      (MemInjMu : Mem.inject (as_inj mu) m1 m2)
      (MatchMu: MATCH mu st1 m1 st2 m2)
      (AtExtSrc : at_external Linear_eff_sem st1 = Some (e, ef_sig, vals1))
      (AtExtTgt : at_external Linear_eff_sem st2 = Some (e', ef_sig', vals2))
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
  after_external Linear_eff_sem (Some ret1) st1 =Some st1' /\
  after_external Linear_eff_sem (Some ret2) st2 = Some st2' /\
  MATCH mu' st1' m1' st2' m2'.
Proof. intros.
simpl.
 destruct MatchMu as [MC [RC [PG [GFP [Glob [VAL [WDmu INJ]]]]]]].
 simpl in *. inv MC; simpl in *; inv AtExtSrc.
 destruct f; inv H1. 
 simpl in AtExtTgt. inv AtExtTgt.
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
assert (PHnu': meminj_preserves_globals (Genv.globalenv prog) (as_inj nu')).
    subst. clear - INC SEP PG Glob WDmu WDnu'.
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
  specialize (IHL _ H2); clear H2.
  apply orb_true_iff in IHL.
  remember (locBlocksSrc nu' b') as l.
  destruct l; apply eq_sym in Heql.
  (*case locBlocksSrc nu' b' = true*)
    clear IHL.
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
          eapply VAL. unfold DOM, DomSrc. rewrite Heql. intuition.
        apply (H0 VB) in H3.
        rewrite (H1 H3) in H5. clear H0 H1.
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
          rewrite (frgnSrc_shared _ WDnu' _ RC). intuition.
  (*case DomSrc nu' b' &&
    (negb (locBlocksSrc nu' b') &&
     REACH m1' (exportedSrc nu' (ret1 :: nil)) b') = true*)
    destruct IHL. congruence.
    apply andb_true_iff in H0. simpl in H0. 
    destruct H0 as [DomNu' Rb']. 
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
           specialize (RC' _ H0). 
           destruct (mappedD_true _ _ RC') as [[? ?] ?].
           eapply as_inj_DomRng; eassumption.
    eapply REACH_cons; try eassumption.
(*assert (RRR: REACH_closed m1' (exportedSrc nu' (ret1 :: nil))).
    intros b Hb. apply REACHAX in Hb.
       destruct Hb as [L HL].
       generalize dependent b.
       induction L ; simpl; intros; inv HL; trivial.
       specialize (IHL _ H1); clear H1.
       unfold exportedSrc.
       eapply REACH_cons; eassumption.*)
    
assert (RRC: REACH_closed m1' (fun b : Values.block =>
                         mapped (as_inj nu') b &&
                           (locBlocksSrc nu' b
                            || DomSrc nu' b &&
                               (negb (locBlocksSrc nu' b) &&
                           REACH m1' (exportedSrc nu' (ret1 :: nil)) b)))).
  eapply REACH_closed_intersection; eassumption.
assert (GFnu': forall b, isGlobalBlock (Genv.globalenv prog) b = true ->
               DomSrc nu' b &&
               (negb (locBlocksSrc nu' b) && REACH m1' (exportedSrc nu' (ret1 :: nil)) b) = true).
     intros. specialize (Glob _ H0).
       assert (FSRC:= extern_incr_frgnBlocksSrc _ _ INC).
          rewrite replace_locals_frgnBlocksSrc in FSRC.
       rewrite FSRC in Glob.
       rewrite (frgnBlocksSrc_locBlocksSrc _ WDnu' _ Glob). 
       apply andb_true_iff; simpl.
        split.
          unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ Glob). intuition.
          apply REACH_nil. unfold exportedSrc.
          rewrite (frgnSrc_shared _ WDnu' _ Glob). intuition.
split.
(*match_states*) (*rewrite replace_externs_vis in *. *)
  clear INCvisNu' UnchLOOR SEP UnchPrivSrc.
  econstructor; try eassumption.
  { (*agree*)
      rewrite restrict_sm_all, vis_restrict_sm,
       replace_externs_as_inj, replace_externs_vis.
       eapply agree_regs_setlist.
         eapply agree_regs_incr. eassumption.
         rewrite restrict_sm_all, vis_restrict_sm.
         rewrite restrict_nest; trivial. 
         rewrite restrict_nest; trivial.
         red; intros. 
          destruct (restrictD_Some _ _ _ _ _ H0).
          apply restrictI_Some. 
            apply extern_incr_as_inj in INC; trivial.
            rewrite replace_locals_as_inj in INC.
            apply INC. trivial.
          apply extern_incr_vis in INC.
            rewrite replace_locals_vis in INC. rewrite INC in H2.
            unfold vis in H2. remember (locBlocksSrc nu' b) as q.    
            destruct q; simpl in *; trivial.
            apply andb_true_iff; split.
              unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ H2). intuition. 
              apply REACH_nil. unfold exportedSrc. rewrite sharedSrc_iff_frgnpub, H2; trivial. 
              intuition.
        apply encode_long_inject.
        rewrite restrict_nest; trivial.
        inv RValInjNu'; econstructor; try reflexivity.
        apply restrictI_Some; trivial.
        remember (locBlocksSrc nu' b1) as q.
        destruct q; simpl; trivial.
        apply andb_true_iff; split.
          eapply as_inj_DomRng; eassumption.
          apply REACH_nil. unfold exportedSrc. 
            apply orb_true_iff; left.
            solve[rewrite getBlocks_char; eexists; left; reflexivity].
      apply map_R_outgoing. }  
  { (*list_match_stackgrames*)
    eapply match_stackframes_forall_restrict_sm_incr. 
      eassumption.
      rewrite replace_externs_as_inj. 
        red; intros. eapply extern_incr_as_inj. eassumption. eassumption. 
          rewrite replace_locals_as_inj. trivial. 
      trivial. trivial.
      rewrite replace_externs_vis. intros.
        exploit extern_incr_vis; try eassumption.
        rewrite replace_locals_vis; intros. rewrite H1 in H0.
        clear H1.
        unfold vis in H0. remember (locBlocksSrc nu' b) as q.    
        destruct q; simpl in *; trivial.
        apply andb_true_iff; split.
          unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ H0). intuition. 
          apply REACH_nil. unfold exportedSrc. rewrite sharedSrc_iff_frgnpub, H0; trivial. intuition.
      rewrite replace_externs_local, replace_externs_vis.
        assert (LOC: local_of mu = local_of nu').
          red in INC. rewrite replace_locals_local in INC. eapply INC.
        rewrite <- LOC in *. 
        red; intros. destruct (restrictD_Some _ _ _ _ _ H0); clear H0.
        apply restrictI_Some; trivial.
        destruct (local_DomRng _ WDmu _ _ _ H1).
        assert (LS: locBlocksSrc mu = locBlocksSrc nu').
          red in INC. rewrite replace_locals_locBlocksSrc in INC. eapply INC.
        rewrite <- LS, H0. trivial. }
destruct (eff_after_check2 _ _ _ _ _ MemInjNu' RValInjNu' 
      _ (eq_refl _) _ (eq_refl _) _ (eq_refl _) WDnu' SMvalNu').
unfold vis in *.
  rewrite replace_externs_locBlocksSrc, replace_externs_frgnBlocksSrc,
  replace_externs_as_inj in *.
intuition.
(*as in selectionproofEFF*)
  red; intros. destruct (GFP _ _ H2). split; trivial.
  eapply extern_incr_as_inj; try eassumption.
  rewrite replace_locals_as_inj. assumption.
Qed. 

Lemma MATCH_initial: forall (v1 v2 : val) (sig : signature) entrypoints
  (EP: In (v1, v2, sig) entrypoints)
  (entry_points_ok : forall (v1 v2 : val) (sig : signature),
                  In (v1, v2, sig) entrypoints ->
                  exists
                    (b : Values.block) f1 f2,
                    v1 = Vptr b Int.zero /\
                    v2 = Vptr b Int.zero /\
                    Genv.find_funct_ptr ge b = Some f1 /\
                    Genv.find_funct_ptr tge b = Some f2)
  (vals1 : list val) c1 (m1 : mem) (j : meminj)
  (vals2 : list val) (m2 : mem) (DomS DomT : Values.block -> bool)
  (Ini : initial_core Linear_eff_sem ge v1 vals1 = Some c1)
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
  initial_core Linear_eff_sem tge v2 vals2 = Some c2 /\
  MATCH 
    (initial_SM DomS DomT
       (REACH m1
          (fun b : Values.block => isGlobalBlock ge b || getBlocks vals1 b))
       (REACH m2
          (fun b : Values.block => isGlobalBlock tge b || getBlocks vals2 b))
       j) c1 m1 c2 m2. 
Proof. intros.
  inversion Ini.
  unfold Linear_initial_core in H0. unfold ge in *. unfold tge in *.
  destruct v1; inv H0.
  remember (Int.eq_dec i Int.zero) as z; destruct z; inv H1. clear Heqz.
  remember (Genv.find_funct_ptr (Genv.globalenv prog) b) as zz; destruct zz; inv H0. 
    apply eq_sym in Heqzz.
  destruct f; try discriminate.
  case_eq (val_casted.val_has_type_list_func vals1
           (sig_args (funsig (Internal f))) && val_casted.vals_defined vals1). 
  2: solve[intros Heq; rewrite Heq in H1; inv H1].
  intros Heq; rewrite Heq in H1; inv H1.
  exploit function_ptr_translated; eauto. intros FP.
  exists (Linear_Callstate nil (transf_fundef (Internal f))
            (Locmap.setlist (Conventions1.loc_arguments (fn_sig f)) 
              (val_casted.encode_longs (sig_args (fn_sig f)) vals2)
              (Locmap.init Vundef))).
  split.
    destruct (entry_points_ok _ _ _ EP) as [b0 [f1 [f2 [A [B [C D]]]]]].
    subst. inv A. rewrite C in Heqzz. inv Heqzz.
    unfold tge in FP. rewrite D in FP. inv FP.
    simpl.
    case_eq (Int.eq_dec Int.zero Int.zero). intros ? e.
    rewrite D.
    assert (val_casted.val_has_type_list_func vals2 (sig_args (funsig (Internal (transf_function f))))=true) as ->.
    { eapply val_casted.val_list_inject_hastype; eauto.
      eapply forall_inject_val_list_inject; eauto.
      destruct (val_casted.vals_defined vals1); auto.
      rewrite andb_comm in Heq; simpl in Heq. solve[inv Heq].
      simpl. simpl in Heq. apply andb_true_iff in Heq; eapply Heq. }
    assert (val_casted.vals_defined vals2=true) as ->.
    { eapply val_casted.val_list_inject_defined.
      eapply forall_inject_val_list_inject; eauto.
      destruct (val_casted.vals_defined vals1); auto.
      rewrite andb_comm in Heq; inv Heq. }
    solve[auto].

    intros CONTRA. solve[elimtype False; auto].
  destruct (core_initial_wd ge tge _ _ _ _ _ _ _  Inj
     VInj J RCH PG GDE HDomS HDomT _ (eq_refl _))
    as [AA [BB [CC [DD [EE [FF GG]]]]]].
  split.
    eapply match_states_call; try eassumption.
    { (*agree_regs*) 
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
      eapply agree_regs_setlist.
          split; intros; constructor.
        rewrite initial_SM_as_inj.
        unfold vis, initial_SM; simpl.
        apply forall_inject_val_list_inject.
        eapply restrict_forall_vals_inject.
        apply val_list_inject_forall_inject.
        apply val_casted.encode_longs_inject; auto.
        apply forall_inject_val_list_inject; auto.
          intros. apply REACH_nil. 
          rewrite orb_true_iff. right. 
          apply (val_casted.getBlocks_encode_longs (sig_args (fn_sig f))); auto.
        red; intros. apply Conventions1.loc_arguments_rec_charact in H. 
           destruct l; try contradiction.
           destruct sl; try contradiction. trivial. }
    constructor.
  rewrite initial_SM_as_inj.
  intuition.
      red; intros. specialize (Genv.find_funct_ptr_not_fresh prog). intros.
         destruct InitMem as [m0 [INIT_MEM [? ?]]].
         specialize (H0 _ _ _ INIT_MEM H). 
         destruct (valid_init_is_global _ R _ INIT_MEM _ H0) as [id Hid]. 
           destruct PG as [PGa [PGb PGc]]. split. eapply PGa; eassumption.
         unfold isGlobalBlock. 
          apply orb_true_iff. left. apply genv2blocksBool_char1.
            simpl. exists id; eassumption.
Qed.

Lemma MATCH_corediagram: forall st1 m1 st1' m1'
         (CS:corestep Linear_eff_sem ge st1 m1 st1' m1')
         st2 mu m2 (MTCH:MATCH mu st1 m1 st2 m2),
exists st2' m2', 
  (corestep_plus Linear_eff_sem tge st2 m2 st2' m2' \/
   (measure st1' < measure st1)%nat /\
   corestep_star Linear_eff_sem tge st2 m2 st2' m2')
/\ exists mu',
  intern_incr mu mu' /\
  sm_inject_separated mu mu' m1 m2 /\
  sm_locally_allocated mu mu' m1 m2 m1' m2' /\
  MATCH mu' st1' m1' st2' m2'.
Proof. intros.
  destruct MTCH as [MS [RC [PG [GFP [Glob [SMV [WD INJ]]]]]]].
  assert (GDE:= GDE_lemma).

  induction CS; intros; try (inv MS); try rewrite remove_unused_labels_cons. 
(* Lgetstack *)
  eexists; eexists; split.
    left; eapply corestep_plus_one.
          econstructor; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
      eapply agree_regs_set; try eassumption.
      eapply agree_regs_undef; try eassumption.
        simpl. eapply AGREE.
    intuition.
(* Lsetstack *)
  eexists; eexists; split.
    left; eapply corestep_plus_one.
          econstructor; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
             eapply agree_regs_setstack; eassumption.
    intuition.
(* Lop *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit (eval_operation_inject'' _ _ ge (as_inj (restrict_sm mu (vis mu)))); try eapply H.
    eapply val_inject_incr; try eapply SPlocal. 
      apply local_in_all.
      apply restrict_sm_WD. assumption. trivial.
    eapply restrict_sm_preserves_globals. assumption.
      unfold vis. intuition.
    eapply agree_regs_list. rewrite restrict_sm_all. eassumption.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
  intros [v2 [EVALOP' VINJ]].
  eexists; eexists; split.
    left; eapply corestep_plus_one.
      econstructor; eauto. instantiate (1 := v2). rewrite <- EVALOP'.
       apply eval_operation_preserved. exact symbols_preserved.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
        rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        rewrite restrict_sm_all in VINJ.
        eapply agree_regs_set; try eassumption.
        eapply agree_regs_undef; eassumption.
   intuition.
(* Lload *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  assert (PGR: meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis; intuition.
  assert (SA: forall (id : ident) (ofs : int),
      val_inject (as_inj (restrict_sm mu (vis mu))) (symbol_address ge id ofs) (symbol_address ge id ofs)).
    intros. eapply symbol_address_inject; try eapply PGR. 
  exploit (eval_addressing_inj ge SA); try eassumption.
     eapply val_inject_incr; try eapply SPlocal. 
       eapply local_in_all; try eassumption.
     rewrite restrict_sm_all. eapply agree_regs_list; try eassumption.
  intros [a' [EA' VA]].
  exploit (Mem.loadv_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eexact H0. 
    apply VA. 
  intros [v' [C D]]. 

  eexists; eexists; split.
    left; eapply corestep_plus_one.
          econstructor; eauto. rewrite <- EA'.
            apply eval_addressing_preserved. exact symbols_preserved. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
        rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        rewrite restrict_sm_all in D.
        eapply agree_regs_set; try eassumption.
    intuition.
(* Lstore *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  assert (PGR: meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis; intuition.
  assert (SA: forall (id : ident) (ofs : int),
      val_inject (as_inj (restrict_sm mu (vis mu))) (symbol_address ge id ofs) (symbol_address ge id ofs)).
    intros. eapply symbol_address_inject; try eapply PGR. 
  exploit (eval_addressing_inj ge SA); try eassumption.
     eapply val_inject_incr; try eapply SPlocal. 
       eapply local_in_all; try eassumption.
     rewrite restrict_sm_all. eapply agree_regs_list; try eassumption.
  intros [a' [EA' VA]]. 
  exploit (Mem.storev_mapped_inject (as_inj mu));
    try eassumption.
    rewrite restrict_sm_all in VA.
      eapply val_inject_incr; try eapply VA. apply restrict_incr.
    eapply val_inject_incr; try eapply AGREE. apply restrict_incr.
  intros [m2' [C D]].
  eexists; eexists; split.
    left; eapply corestep_plus_one.
           econstructor; eauto.
         rewrite <- EA'; apply eval_addressing_preserved. 
           exact symbols_preserved.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj. 
  split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
      try rewrite (storev_freshloc _ _ _ _ _ H0); 
      try rewrite (storev_freshloc _ _ _ _ _ C); intuition. 
  destruct a; inv H0.
  rewrite restrict_sm_all in VA. inv VA.
  destruct (restrictD_Some _ _ _ _ _ H3).
  simpl in C.
  assert (SMV': sm_valid mu m' m2').
    split; intros. 
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
  split; intuition. 
    econstructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        eapply agree_regs_undef; eassumption.
      eapply REACH_Store; try eassumption. 
          intros b' Hb'. rewrite getBlocks_char in Hb'. destruct Hb' as [off Hoff].
                  destruct Hoff; try contradiction.
                  destruct AGREE as [AGREE_R _].
                  specialize (AGREE_R src). 
                   rewrite H4 in AGREE_R; inv AGREE_R.   
                   destruct (restrictD_Some _ _ _ _ _ H8); trivial.
(* Lcall *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit agree_find_function_translated; try eassumption.
    eapply agree_regs_incr; try eapply AGREE. apply restrict_incr. 
  intros TFD.
  eexists; eexists; split.
    left; eapply corestep_plus_one.
       econstructor. eassumption.
        symmetry; apply sig_function_translated.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. constructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
      constructor; auto.
        constructor; auto.
          rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
      eapply incl_cons_inv. eassumption.
    intuition.
(* Ltailcall *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  specialize (match_parent_locset _ _ _ STACKS); intros parentsAGREE.
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in parentsAGREE; trivial.
  assert (AGREERET: agree_regs (restrict (as_inj mu) (vis mu)) (LTL.return_regs (parent_locset s) rs) (LTL.return_regs (parent_locset ts) tls)).
     eapply agree_regs_return; eassumption. 
  exploit agree_find_function_translated; try eassumption.
    eapply agree_regs_incr; try eapply AGREERET. apply restrict_incr.
  intros TFD.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  destruct SPlocal as [SPL1 SPL2]. inv SPL1. 
  destruct (SPL2 _ _ (eq_refl _)) as [spb SPB]; clear SPL2.
  edestruct free_parallel_inject as [tm' []]; eauto.
    eapply restrictD_Some. rewrite restrict_sm_all in SPB; eassumption.
  simpl in H; rewrite Zplus_0_r in H.
  rewrite (local_in_all _ WDR _ _ _ H3) in SPB; inv SPB.

  eexists; eexists; split.
    left; eapply corestep_plus_one.
         econstructor. reflexivity. eassumption. 
          symmetry; apply sig_function_translated.
          eassumption.
  assert (SMV': sm_valid mu m' tm').
    split; intros;  
      eapply free_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
          try rewrite (freshloc_free _ _ _ _ _ H2);
          try rewrite (freshloc_free _ _ _ _ _ H); intuition.
  split. econstructor; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
  intuition.
      eapply REACH_closed_free; try eassumption.
         
(* Lbuiltin *)
  inv H. 
  assert (ArgsInj: val_list_inject (restrict (as_inj mu) (vis mu))
            (decode_longs (sig_args (ef_sig ef)) (LTL.reglist rs args))
            (decode_longs (sig_args (ef_sig ef)) (LTL.reglist tls args))).
    eapply agree_regs_list in AGREE.
    rewrite restrict_sm_all, vis_restrict_sm, restrict_nest in AGREE; trivial.
    eapply decode_longs_inject; eassumption.
  exploit (inlineable_extern_inject ge tge); try eassumption.
  intros [mu' [v' [m'' [TEC [ResInj [MINJ' [UNMAPPED [LOOR [INC [SEP [LOCALLOC [WD' [SMV' RC']]]]]]]]]]]]]. 
 
  eexists; eexists; split.
    left. eapply corestep_plus_one.
           econstructor; eauto.
            econstructor. eassumption. reflexivity.
  exists mu'.
  split; trivial. 
  split; trivial.
  split; trivial.
  split. econstructor; eauto.
      eapply list_match_stackframes_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption.
        apply restrict_sm_WD; trivial.
      eapply incl_cons_inv; eassumption.
      eapply agree_regs_set_regs; try eassumption. 
       eapply agree_regs_undef.
       rewrite restrict_sm_all, vis_restrict_sm, restrict_nest in AGREE; trivial.
       rewrite restrict_sm_all, vis_restrict_sm, restrict_nest; trivial.
       eapply agree_regs_incr; try eassumption.
        eapply intern_incr_restrict; eassumption.
      rewrite restrict_sm_all, vis_restrict_sm, restrict_nest; trivial.
        eapply encode_long_inject; eassumption.
      eapply sp_mapped_intern_incr; try eassumption.
         eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; trivial.
    intuition.
      apply intern_incr_as_inj in INC; trivial.
        apply sm_inject_separated_mem in SEP; trivial.
        eapply meminj_preserves_incr_sep; eassumption. 
      red; intros. destruct (GFP _ _ H1).
          split; trivial.
          eapply intern_incr_as_inj; eassumption.
      assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INC.
          rewrite <- FRG. eapply (Glob _ H1).

(* Lannot not supported
  eexists; eexists; split.
    left; eapply corestep_plus_one.
  left; econstructor; split.
  econstructor; eauto. eapply external_call_symbols_preserved'; eauto.
  exact symbols_preserved.  exact varinfo_preserved.
  econstructor; eauto with coqlib.*)

(* Llabel *)
  case_eq (Labelset.mem lbl (labels_branched_to (fn_code f))); intros.
  (* not eliminated *)
  eexists; eexists; split.
    left; eapply corestep_plus_one. constructor.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split.  econstructor; eauto with coqlib.
    intuition.
  (* eliminated *)
  eexists; eexists; split.
    right. split. simpl. omega. eapply corestep_star_zero.
  exists mu. 
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
    intuition.
(* Lgoto *)
  eexists; eexists; split.
    left; eapply corestep_plus_one.
       econstructor. eapply find_label_translated; eauto. red; auto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto. eapply find_label_incl; eauto.
    intuition.
(* Lcond taken *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit eval_condition_inject; try eassumption.
    eapply agree_regs_list; try eassumption.
    eapply agree_regs_incr; try eassumption. apply restrict_incr.
  intros EC. 
  eexists; eexists; split.
    left; eapply corestep_plus_one.
          econstructor. auto. eauto. eapply find_label_translated; eauto. red; auto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto. eapply find_label_incl; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
(* Lcond not taken *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit eval_condition_inject; try eassumption.
    eapply agree_regs_list; try eassumption.
    eapply agree_regs_incr; try eassumption. apply restrict_incr.
  intros EC. 
  eexists; eexists; split.
    left; eapply corestep_plus_one.
          eapply lin_exec_Lcond_false; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
(* Ljumptable *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (Vinj: val_inject (restrict (as_inj mu) (vis mu)) (rs (R arg)) (tls (R arg))).
    eapply AGREE.
  rewrite H in Vinj. inv Vinj.
  eexists; eexists; split.
    left.  eapply corestep_plus_one. 
         econstructor. eauto. eauto. eapply find_label_translated; eauto. 
         red. eapply list_nth_z_in; eauto. eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto. eapply find_label_incl; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
(* Lreturn *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  destruct SPlocal as [SPL1 SPL2]; inv SPL1.
  destruct (SPL2 _ _ (eq_refl _)) as [spb SPB]; clear SPL2.
  edestruct free_parallel_inject as [tm' []]; eauto.
    eapply restrictD_Some. rewrite restrict_sm_all in SPB; eassumption.
  simpl in H0; rewrite Zplus_0_r in H0.
  rewrite (local_in_all _ WDR _ _ _ H2) in SPB; inv SPB.

  specialize (match_parent_locset _ _ _ STACKS); intros parentsAGREE.
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in parentsAGREE; trivial.
  assert (AGREERET: agree_regs (restrict (as_inj mu) (vis mu)) (LTL.return_regs (parent_locset s) rs) (LTL.return_regs (parent_locset ts) tls)).
     eapply agree_regs_return; eassumption.
  eexists; eexists; split.
    left; eapply corestep_plus_one.
          econstructor; eauto.
  assert (SMV': sm_valid mu m' tm').
    split; intros;  
      eapply free_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
          try rewrite (freshloc_free _ _ _ _ _ H0);
          try rewrite (freshloc_free _ _ _ _ _ H); intuition.
    split. econstructor; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition. 
      eapply REACH_closed_free; try eassumption.
(* internal function *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  edestruct alloc_parallel_intern as 
     [mu' [tm' [b' [Alloc' [MInj' [IntInc [mu'SP [Ai' [SEP [LocAlloc [WD' [SMV' RC']]]]]]]]]]]]; 
     eauto; try apply Zle_refl.
  eexists; eexists; split.
    left; eapply corestep_plus_one.
       econstructor; simpl; eauto.
  exists mu'. 
  split. assumption.
  split. assumption.
  split. assumption.
  split. econstructor; eauto with coqlib.       
      eapply list_match_stackframes_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; try eassumption. trivial.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
        eapply agree_regs_undef.
        eapply agree_regs_call_regs.
        eapply agree_regs_incr. eassumption. apply intern_incr_restrict; eassumption.
      destruct (joinD_Some _ _ _ _ _ mu'SP) as [EXT | [EXT LOC]]; clear mu'SP.
        assert (extern_of mu = extern_of mu') by eapply IntInc.
        rewrite <- H0 in EXT; clear H0.
        elim (Mem.fresh_block_alloc _ _ _ _ _ H).
        eapply SMV. 
          eapply as_inj_DomRng; trivial.
          apply extern_in_all; eassumption.
      split. rewrite restrict_sm_local.
        econstructor. apply restrictI_Some; try eassumption.
          unfold vis. destruct (local_DomRng _ WD' _ _ _ LOC). rewrite H0; trivial.
        rewrite Int.add_zero. trivial. 
      intros. inv H0. rewrite restrict_sm_all.
         eexists. apply restrictI_Some. apply local_in_all; eassumption.
           unfold vis. destruct (local_DomRng _ WD' _ _ _ LOC). rewrite H0; trivial.
    (*as in selectionproofEff*)
     intuition.
     apply meminj_preserves_incr_sep_vb with (j:=as_inj mu)(m0:=m)(tm:=m2); try eassumption. 
       intros. apply as_inj_DomRng in H1.
               split; eapply SMV; eapply H1.
       assumption.
       apply intern_incr_as_inj; eassumption.
       apply sm_inject_separated_mem. assumption.
       assumption.
     red; intros. destruct (GFP _ _ H1). split; trivial.
          eapply intern_incr_as_inj; eassumption.
     assert (FF: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply IntInc.
       apply Glob in H1. rewrite <-FF; trivial.

(* external function -- no case
  left; econstructor; split.
  econstructor; eauto. eapply external_call_symbols_preserved'; eauto.
  exact symbols_preserved.  exact varinfo_preserved.
  econstructor; eauto with coqlib.*)
(* return *)
  inv H5. inv H1.
  eexists; eexists; split.
    left; eapply corestep_plus_one. econstructor; eauto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
    split. econstructor; eauto.
    intuition.
Qed.

Lemma MATCH_effcorediagram: forall st1 m1 st1' m1' U1
         (CS:effstep Linear_eff_sem ge U1 st1 m1 st1' m1')
         st2 mu m2 (U1Vis: forall b ofs, U1 b ofs = true -> vis mu b = true)
         (MTCH:MATCH mu st1 m1 st2 m2),
exists st2' m2' U2, 
  (effstep_plus Linear_eff_sem tge U2 st2 m2 st2' m2' \/
   (measure st1' < measure st1)%nat /\
   effstep_star Linear_eff_sem tge U2 st2 m2 st2' m2')
/\ exists mu',
  intern_incr mu mu' /\
  sm_inject_separated mu mu' m1 m2 /\
  sm_locally_allocated mu mu' m1 m2 m1' m2' /\
  MATCH mu' st1' m1' st2' m2' /\
  (forall (b : block) (ofs : Z),
      U2 b ofs = true ->
      visTgt mu b = true /\
      (locBlocksTgt mu b = false ->
       exists (b1 : block) (delta1 : Z),
         foreign_of mu b1 = Some (b, delta1) /\
         U1 b1 (ofs - delta1) = true /\
         Mem.perm m1 b1 (ofs - delta1) Max Nonempty)).
Proof. intros.
  destruct MTCH as [MS [RC [PG [GFP [Glob [SMV [WD INJ]]]]]]].
  assert (GDE:= GDE_lemma).
  induction CS; intros; try (inv MS); try rewrite remove_unused_labels_cons. 
(* Lgetstack *)
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_one.
          econstructor; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
      eapply agree_regs_set; try eassumption.
      eapply agree_regs_undef; try eassumption.
        simpl. eapply AGREE.
    intuition.
  intuition.
(* Lsetstack *)
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_one.
          econstructor; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
             eapply agree_regs_setstack; eassumption.
      intuition.
    intuition.
(* Lop *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit (eval_operation_inject'' _ _ ge (as_inj (restrict_sm mu (vis mu)))); try eapply H.
    eapply val_inject_incr; try eapply SPlocal. 
      apply local_in_all.
      apply restrict_sm_WD. assumption. trivial.
    eapply restrict_sm_preserves_globals. assumption.
      unfold vis. intuition.
    eapply agree_regs_list. rewrite restrict_sm_all. eassumption.
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
  intros [v2 [EVALOP' VINJ]].
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
      econstructor; eauto. instantiate (1 := v2). rewrite <- EVALOP'.
       apply eval_operation_preserved. exact symbols_preserved.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
        rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        rewrite restrict_sm_all in VINJ.
        eapply agree_regs_set; try eassumption.
        eapply agree_regs_undef; eassumption.
   intuition.
  intuition.
(* Lload *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  assert (PGR: meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis; intuition.
  assert (SA: forall (id : ident) (ofs : int),
      val_inject (as_inj (restrict_sm mu (vis mu))) (symbol_address ge id ofs) (symbol_address ge id ofs)).
    intros. eapply symbol_address_inject; try eapply PGR. 
  exploit (eval_addressing_inj ge SA); try eassumption.
     eapply val_inject_incr; try eapply SPlocal. 
       eapply local_in_all; try eassumption.
     rewrite restrict_sm_all. eapply agree_regs_list; try eassumption.
  intros [a' [EA' VA]].
  exploit (Mem.loadv_inject (as_inj (restrict_sm mu (vis mu)))).
    rewrite restrict_sm_all. eapply inject_restrict; eassumption.
    eexact H0. 
    apply VA. 
  intros [v' [C D]]. 

  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
          econstructor; eauto. rewrite <- EA'.
            apply eval_addressing_preserved. exact symbols_preserved. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
        rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        rewrite restrict_sm_all in D.
        eapply agree_regs_set; try eassumption.
    intuition.
  intuition.
(* Lstore *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  assert (PGR: meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis; intuition.
  assert (SA: forall (id : ident) (ofs : int),
      val_inject (as_inj (restrict_sm mu (vis mu))) (symbol_address ge id ofs) (symbol_address ge id ofs)).
    intros. eapply symbol_address_inject; try eapply PGR. 
  exploit (eval_addressing_inj ge SA); try eassumption.
     eapply val_inject_incr; try eapply SPlocal. 
       eapply local_in_all; try eassumption.
     rewrite restrict_sm_all. eapply agree_regs_list; try eassumption.
  intros [a' [EA' VA]]. 
  exploit (Mem.storev_mapped_inject (as_inj mu));
    try eassumption.
    rewrite restrict_sm_all in VA.
      eapply val_inject_incr; try eapply VA. apply restrict_incr.
    eapply val_inject_incr; try eapply AGREE. apply restrict_incr.
  intros [m2' [C D]].
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
           econstructor; eauto.
         rewrite <- EA'; apply eval_addressing_preserved. 
           exact symbols_preserved.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj. 
  split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
      try rewrite (storev_freshloc _ _ _ _ _ H0); 
      try rewrite (storev_freshloc _ _ _ _ _ C); intuition. 
  destruct a; inv H0.
  rewrite restrict_sm_all in VA. inv VA.
  destruct (restrictD_Some _ _ _ _ _ H3).
  simpl in C.
  assert (SMV': sm_valid mu m' m2').
    split; intros. 
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
      eapply Mem.store_valid_block_1; try eassumption.
        eapply SMV; assumption.
  split. split; intuition. 
    econstructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
        eapply agree_regs_undef; eassumption.
      eapply REACH_Store; try eassumption. 
          intros b' Hb'. rewrite getBlocks_char in Hb'. destruct Hb' as [off Hoff].
                  destruct Hoff; try contradiction.
                  destruct AGREE as [AGREE_R _].
                  specialize (AGREE_R src). 
                   rewrite H4 in AGREE_R; inv AGREE_R.   
                   destruct (restrictD_Some _ _ _ _ _ H8); trivial.
  intuition.
    intros. apply StoreEffectD in H4. destruct H4 as [z [HI Ibounds]].
            apply eq_sym in HI. inv HI. 
            eapply visPropagateR; eassumption.
    eapply StoreEffect_PropagateLeft; try eassumption.
     econstructor. eassumption. trivial.
     apply C.
(* Lcall *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit agree_find_function_translated; try eassumption.
    eapply agree_regs_incr; try eapply AGREE. apply restrict_incr. 
  intros TFD.
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
       econstructor. eassumption.
        symmetry; apply sig_function_translated.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. constructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
      constructor; auto.
        constructor; auto.
          rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
      eapply incl_cons_inv. eassumption.
    intuition.
  intuition.
(* Ltailcall *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  specialize (match_parent_locset _ _ _ STACKS); intros parentsAGREE.
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in parentsAGREE; trivial.
  assert (AGREERET: agree_regs (restrict (as_inj mu) (vis mu)) (LTL.return_regs (parent_locset s) rs) (LTL.return_regs (parent_locset ts) tls)).
     eapply agree_regs_return; eassumption. 
  exploit agree_find_function_translated; try eassumption.
    eapply agree_regs_incr; try eapply AGREERET. apply restrict_incr.
  intros TFD.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  destruct SPlocal as [SPL1 SPL2]. inv SPL1. 
  destruct (SPL2 _ _ (eq_refl _)) as [spb SPB]; clear SPL2.
  edestruct free_parallel_inject as [tm' []]; eauto.
    eapply restrictD_Some. rewrite restrict_sm_all in SPB; eassumption.
  simpl in H; rewrite Zplus_0_r in H.
  rewrite (local_in_all _ WDR _ _ _ H3) in SPB; inv SPB.

  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
         econstructor. reflexivity. eassumption. 
          symmetry; apply sig_function_translated.
          eassumption.
  assert (SMV': sm_valid mu m' tm').
    split; intros;  
      eapply free_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  exists mu.
  split. apply intern_incr_refl. 
  split. apply sm_inject_separated_same_sminj.
  split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
          try rewrite (freshloc_free _ _ _ _ _ H2);
          try rewrite (freshloc_free _ _ _ _ _ H); intuition.
  split. split. econstructor; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; trivial.
    intuition.
      eapply REACH_closed_free; try eassumption.
  intros.
    apply local_in_all in H3; trivial.
    rewrite restrict_sm_all in H3.
    destruct (restrictD_Some _ _ _ _ _ H3).
    split. apply FreeEffectD in H4.
           destruct H4; subst. 
           eapply visPropagate; try eassumption.
    eapply FreeEffect_PropagateLeft; try eassumption.
         
(* Lbuiltin *)
  inv H. 
  assert (ArgsInj: val_list_inject (restrict (as_inj mu) (vis mu))
            (decode_longs (sig_args (ef_sig ef)) (LTL.reglist rs args))
            (decode_longs (sig_args (ef_sig ef)) (LTL.reglist tls args))).
    eapply agree_regs_list in AGREE.
    rewrite restrict_sm_all, vis_restrict_sm, restrict_nest in AGREE; trivial.
    eapply decode_longs_inject; eassumption.
  exploit (inlineable_extern_inject ge tge); try eassumption.
  intros [mu' [v' [m'' [TEC [ResInj [MINJ' [UNMAPPED [LOOR [INC [SEP [LOCALLOC [WD' [SMV' RC']]]]]]]]]]]]]. 
 
  eexists; eexists; eexists; split. 
    left. eapply effstep_plus_one.
           econstructor; eauto.
            econstructor. eassumption. reflexivity.
  exists mu'.
  split; trivial. 
  split; trivial.
  split; trivial.
  split. split. econstructor; eauto.
      eapply list_match_stackframes_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption.
        apply restrict_sm_WD; trivial.
      eapply incl_cons_inv; eassumption.
      eapply agree_regs_set_regs; try eassumption. 
       eapply agree_regs_undef.
       rewrite restrict_sm_all, vis_restrict_sm, restrict_nest in AGREE; trivial.
       rewrite restrict_sm_all, vis_restrict_sm, restrict_nest; trivial.
       eapply agree_regs_incr; try eassumption.
        eapply intern_incr_restrict; eassumption.
      rewrite restrict_sm_all, vis_restrict_sm, restrict_nest; trivial.
        eapply encode_long_inject; eassumption.
      eapply sp_mapped_intern_incr; try eassumption.
         eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; trivial.
    intuition.
      apply intern_incr_as_inj in INC; trivial.
        apply sm_inject_separated_mem in SEP; trivial.
        eapply meminj_preserves_incr_sep; eassumption. 
      red; intros. destruct (GFP _ _ H1).
          split; trivial.
          eapply intern_incr_as_inj; eassumption.
      assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INC.
          rewrite <- FRG. eapply (Glob _ H1).
  intros.
    eapply BuiltinEffect_Propagate; try eassumption.  

(* Lannot not supported
  eexists; eexists; eexists; split.
    left; eapply effstep_plus_one.
  left; econstructor; split.
  econstructor; eauto. eapply external_call_symbols_preserved'; eauto.
  exact symbols_preserved.  exact varinfo_preserved.
  econstructor; eauto with coqlib.*)

(* Llabel *)
  case_eq (Labelset.mem lbl (labels_branched_to (fn_code f))); intros.
  (* not eliminated *)
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one. constructor.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
      intuition.
  intuition.
  (* eliminated *)
  eexists; eexists; eexists; split. 
    right. split. simpl. omega. eapply effstep_star_zero.
  exists mu. 
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
      intuition.
  intuition.
(* Lgoto *)
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
       econstructor. eapply find_label_translated; eauto. red; auto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto. eapply find_label_incl; eauto.
      intuition.
  intuition.
(* Lcond taken *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit eval_condition_inject; try eassumption.
    eapply agree_regs_list; try eassumption.
    eapply agree_regs_incr; try eassumption. apply restrict_incr.
  intros EC. 
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
          econstructor. auto. eauto. eapply find_label_translated; eauto. red; auto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto. eapply find_label_incl; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
  intuition.
(* Lcond not taken *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  exploit eval_condition_inject; try eassumption.
    eapply agree_regs_list; try eassumption.
    eapply agree_regs_incr; try eassumption. apply restrict_incr.
  intros EC. 
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
          eapply lin_effexec_Lcond_false; eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto with coqlib.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
  intuition.
(* Ljumptable *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (Vinj: val_inject (restrict (as_inj mu) (vis mu)) (rs (R arg)) (tls (R arg))).
    eapply AGREE.
  rewrite H in Vinj. inv Vinj.
  eexists; eexists; eexists; split. 
    left.  eapply effstep_plus_one. 
         econstructor. eauto. eauto. eapply find_label_translated; eauto. 
         red. eapply list_nth_z_in; eauto. eauto.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto. eapply find_label_incl; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition.
  intuition.
(* Lreturn *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  assert (WDR: SM_wd (restrict_sm mu (vis mu))).
   apply restrict_sm_WD; try eassumption. trivial.
  destruct SPlocal as [SPL1 SPL2]; inv SPL1.
  destruct (SPL2 _ _ (eq_refl _)) as [spb SPB]; clear SPL2.
  edestruct free_parallel_inject as [tm' []]; eauto.
    eapply restrictD_Some. rewrite restrict_sm_all in SPB; eassumption.
  simpl in H0; rewrite Zplus_0_r in H0.
  rewrite (local_in_all _ WDR _ _ _ H2) in SPB; inv SPB.

  specialize (match_parent_locset _ _ _ STACKS); intros parentsAGREE.
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in parentsAGREE; trivial.
  assert (AGREERET: agree_regs (restrict (as_inj mu) (vis mu)) (LTL.return_regs (parent_locset s) rs) (LTL.return_regs (parent_locset ts) tls)).
     eapply agree_regs_return; eassumption.
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
          econstructor; eauto.
  assert (SMV': sm_valid mu m' tm').
    split; intros;  
      eapply free_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
      repeat split; apply extensionality; intros bb; 
          try rewrite (freshloc_free _ _ _ _ _ H0);
          try rewrite (freshloc_free _ _ _ _ _ H); intuition.
  split. split. econstructor; eauto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
    intuition. 
      eapply REACH_closed_free; try eassumption.
  intros.
    apply local_in_all in H2; trivial.
    rewrite restrict_sm_all in H2.
    destruct (restrictD_Some _ _ _ _ _ H2).
    split. apply FreeEffectD in H3.
           destruct H3; subst. 
           eapply visPropagate; try eassumption.
    eapply FreeEffect_PropagateLeft; try eassumption.
(* internal function *)
  rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
  edestruct alloc_parallel_intern as 
     [mu' [tm' [b' [Alloc' [MInj' [IntInc [mu'SP [Ai' [SEP [LocAlloc [WD' [SMV' RC']]]]]]]]]]]]; 
     eauto; try apply Zle_refl.
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one.
       econstructor; simpl; eauto.
  exists mu'. 
  split. assumption.
  split. assumption.
  split. assumption.
  split. split. econstructor; eauto with coqlib.       
      eapply list_match_stackframes_intern_incr; try eassumption.
        eapply restrict_sm_intern_incr; eassumption.
         apply restrict_sm_WD; try eassumption. trivial.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest; eauto.
        eapply agree_regs_undef.
        eapply agree_regs_call_regs.
        eapply agree_regs_incr. eassumption. apply intern_incr_restrict; eassumption.
      destruct (joinD_Some _ _ _ _ _ mu'SP) as [EXT | [EXT LOC]]; clear mu'SP.
        assert (extern_of mu = extern_of mu') by eapply IntInc.
        rewrite <- H0 in EXT; clear H0.
        elim (Mem.fresh_block_alloc _ _ _ _ _ H).
        eapply SMV. 
          eapply as_inj_DomRng; trivial.
          apply extern_in_all; eassumption.
      split. rewrite restrict_sm_local.
        econstructor. apply restrictI_Some; try eassumption.
          unfold vis. destruct (local_DomRng _ WD' _ _ _ LOC). rewrite H0; trivial.
        rewrite Int.add_zero. trivial. 
      intros. inv H0. rewrite restrict_sm_all.
         eexists. apply restrictI_Some. apply local_in_all; eassumption.
           unfold vis. destruct (local_DomRng _ WD' _ _ _ LOC). rewrite H0; trivial.
    (*as in selectionproofEff*)
     intuition.
     apply meminj_preserves_incr_sep_vb with (j:=as_inj mu)(m0:=m)(tm:=m2); try eassumption. 
       intros. apply as_inj_DomRng in H1.
               split; eapply SMV; eapply H1.
       assumption.
       apply intern_incr_as_inj; eassumption.
       apply sm_inject_separated_mem. assumption.
       assumption.
     red; intros. destruct (GFP _ _ H1). split; trivial.
          eapply intern_incr_as_inj; eassumption.
     assert (FF: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply IntInc.
       apply Glob in H1. rewrite <-FF; trivial.
  intuition.

(* external function -- no case
  left; econstructor; split.
  econstructor; eauto. eapply external_call_symbols_preserved'; eauto.
  exact symbols_preserved.  exact varinfo_preserved.
  econstructor; eauto with coqlib.*)

(* return *)
  inv H5. inv H1.
  eexists; eexists; eexists; split. 
    left; eapply effstep_plus_one. econstructor; eauto. 
  exists mu.
    split. apply intern_incr_refl. 
    split. apply sm_inject_separated_same_sminj. 
    split. rewrite sm_locally_allocatedChar.
        repeat split; extensionality bb; 
          try rewrite freshloc_irrefl; intuition.
  split. split. econstructor; eauto.
    intuition.
  intuition.
Qed.

(*program structure not yet updated to module*)
Theorem transl_program_correct:
  forall (*(TRANSL: sel_program prog = OK tprog)*)
         (LNR: list_norepet (map fst (prog_defs prog)))
         entrypoints
         (entry_points_ok : 
            forall v1 v2 sig,
              In (v1, v2, sig) entrypoints -> 
              exists b f1 f2, 
                v1 = Vptr b Int.zero 
                /\ v2 = Vptr b Int.zero
                /\ Genv.find_funct_ptr ge b = Some f1
                /\ Genv.find_funct_ptr tge b = Some f2)
         (init_mem: exists m0, Genv.init_mem prog = Some m0),
SM_simulation.SM_simulation_inject Linear_eff_sem 
  Linear_eff_sem ge tge entrypoints.
Proof.
intros.
eapply (SM_simulation.Build_SM_simulation_inject) with
  (match_state := fun d mu c1 m1 c2 m2 => MATCH mu c1 m1 c2 m2 /\ d=c1).
eapply lt_state_wf.
(*MATCH_WD*)
intros. apply H.
(*genvs_dom_eq*)
apply GDE_lemma.
(*match_visible*)
  intros. destruct MC; subst. eapply MATCH_PG; eassumption.
(*match_reach_closed*)
intros. apply H.
(*genvs_restrict*)
  intros. destruct H; subst. 
  split; trivial. eapply MATCH_restrict; eassumption.
(*match_valid*)
  intros. apply H.
(*initial_core*)
  { intros. 
    exploit (MATCH_initial _ _ _ _ H entry_points_ok); eauto.
    destruct init_mem as [m0 INIT].
    exists m0; split; auto.
    unfold meminj_preserves_globals in H3.    
    destruct H3 as [A [B C]].

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
    apply A in H3.
    assert (Mem.valid_block m1 (Mem.nextblock m1)).
      eapply Mem.valid_block_inject_1; eauto.
    clear - H8; unfold Mem.valid_block in H8.
    xomega.

    destruct (P (Mem.nextblock m0) (Mem.nextblock m2)); auto.
    exfalso. 
    destruct (D _ p).
    apply A in H3.
    assert (Mem.valid_block m2 (Mem.nextblock m2)).
      eapply Mem.valid_block_inject_2; eauto.
    clear - H8; unfold Mem.valid_block in H8.
    xomega.
    
    intros b LT.    
    unfold ge. 
    apply valid_init_is_global with (b0 := b) in INIT.
    eapply INIT; auto.
    apply LNR.
    apply LT.

    apply GDE_lemma.
    intros [c2 [Ini2 C2]]. exists c1, c2; intuition. }
(*corediagram*)
  { intros. destruct H0 as [MTCH CS]; subst. 
    exploit MATCH_corediagram; eauto.
    intros [st2' [m2' [CS' [mu' MU']]]].
    exists st2', m2', st1', mu'.
    split; try eapply MU'.
    split; try eapply MU'.
    split; try eapply MU'.
    split. split; trivial. apply MU'.
    destruct CS'. 
      left; trivial.
    destruct H0. right. unfold lt_state.
      split; assumption. }
(*effcorediagram*)
  { intros. destruct H0 as [MTCH CS]; subst. 
    exploit MATCH_effcorediagram; eauto.
    intros [st2' [m2' [U2 [CS' [mu' MU']]]]].
    exists st2', m2', st1', mu'.
    split; try eapply MU'.
    split; try eapply MU'.
    split; try eapply MU'.
    split. split; trivial. apply MU'.
    exists U2.
    split. destruct CS'. 
        left; trivial.
      destruct H0. right. unfold lt_state.
        split; assumption.
    eapply MU'. }
(*halted*)
  { intros. destruct H as [MTCH CD]; subst.
    destruct MTCH as [MC [RC [PG [GFP [Glob [VAL [WD INJ]]]]]]].
    revert H0. simpl. destruct c1; try solve[inversion 1]. inversion 1.
    revert H1. destruct stack; try solve[inversion 1].
    destruct retty.
    { inv MC.
    destruct t; try solve[inversion 1]; simpl. inversion 1; subst. clear H1.
    + exists (tls (R AX)). split; auto. split. 
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
      destruct AGREE as [AGREE_R _]; specialize (AGREE_R AX); auto.
      inv H6; auto. 
    + inversion 1; subst. exists (tls (R FP0)). split; auto. split.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
      destruct AGREE as [AGREE_R _]; specialize (AGREE_R FP0); auto.
      inv H6; auto. 
    + inversion 1; subst. exists (Val.longofwords (tls (R DX)) (tls (R AX))).
      split; auto. split; auto. 
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
      apply val_longofwords_inject; auto.
      solve[destruct AGREE as [AGREE_R _]; specialize (AGREE_R DX); auto].
      solve[destruct AGREE as [AGREE_R _]; specialize (AGREE_R AX); auto].
      inv H6; auto. 
    + inversion 1; subst. exists (tls (R FP0)). split; auto. split; auto.
      rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
      destruct AGREE as [AGREE_R _]; specialize (AGREE_R FP0); auto.
      inv H6; auto. }
    { inversion 1; subst. simpl in *.
      inv MC. simpl. exists (tls (R AX)). split; trivial.
      split. rewrite vis_restrict_sm, restrict_sm_all, restrict_nest in AGREE; trivial.
        destruct AGREE as [AGREE_R _]. apply (AGREE_R AX).
      inv H7; auto. } }
(*atExternal*)
  { intros. destruct H as [MTCH CD]; subst cd.
    exploit MATCH_atExternal; try eassumption.
     intros [INJ [vals2 [HVals2a [HVals2b Hvals2c]]]]. 
     split. assumption.
     exists vals2. split; trivial. split; trivial.
     intros. destruct (Hvals2c _ _ pubSrcHyp pubTgtHyp _ Hnu).
       intuition. }
(*afterExternal*)
  { intros. destruct MatchMu as [MTCH CD]; subst cd.
    exploit MATCH_afterExternal.
     apply GDE_lemma. apply MemInjMu. apply MTCH.
     eassumption. eassumption. eassumption.
     eapply pubSrcHyp. eapply pubTgtHyp. eassumption.
     eassumption. eassumption. eassumption. 
     eassumption. eassumption. eassumption. 
     eassumption.
     intros. destruct (H FwdTgt _ frgnSrcHyp _  frgnTgtHyp 
              _ Mu'Hyp UnchPrivSrc UnchLOOR)
             as [st1' [st2' [AftExtSrc [AftExtTgt MTCH']]]].
            exists st1', st1', st2'; eauto. }
Qed.

End CLEANUP.

