Require Import Coqlib.
Require Import AST.
Require Import Integers.
Require Import Values.
Require Import Memory.
Require Export Maps.
Require Import Events.
Require Import Globalenvs.

Require Import mem_lemmas. (*for mem_forward*)
Require Import semantics.
Require Import effect_semantics.

Require Import Op. (*for eval_operation etc*)
Require Import Locations. (*for locmap.set etc*)
Require Import Conventions. (*for loc_result*)

Require Import LTL.
Require Import LTL_coop.
Require Import BuiltinEffects.

Section LTL_EFF.
Variable hf : I64Helpers.helper_functions.

Inductive ltl_effstep (g:genv):  (block -> Z -> bool) ->
            LTL_core -> mem -> LTL_core -> mem -> Prop :=
  | ltl_effstep_start_block: forall s f sp pc rs m bb retty,
      (fn_code f)!pc = Some bb ->
      ltl_effstep g EmptyEffect (LTL_State s f sp pc rs retty) m
        (LTL_Block s f sp bb rs retty) m
  | ltl_effstep_Lop: forall s f sp op args res bb rs m v rs' retty,
      eval_operation g sp op (reglist rs args) m = Some v ->
      rs' = Locmap.set (R res) v (undef_regs (destroyed_by_op op) rs) ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lop op args res :: bb) rs retty) m
        (LTL_Block s f sp bb rs' retty) m
  | ltl_effstep_Lload: forall s f sp chunk addr args dst bb rs m a v rs' retty,
      eval_addressing g sp addr (reglist rs args) = Some a ->
      Mem.loadv chunk m a = Some v ->
      rs' = Locmap.set (R dst) v (undef_regs (destroyed_by_load chunk addr) rs) ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lload chunk addr args dst :: bb) rs retty) m
        (LTL_Block s f sp bb rs' retty) m
  | ltl_effstep_Lgetstack: forall s f sp sl ofs ty dst bb rs m rs' retty,
      rs' = Locmap.set (R dst) (rs (S sl ofs ty)) (undef_regs (destroyed_by_getstack sl) rs) ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lgetstack sl ofs ty dst :: bb) rs retty) m
        (LTL_Block s f sp bb rs' retty) m
  | ltl_effstep_Lsetstack: forall s f sp src sl ofs ty bb rs m rs' retty,
      rs' = Locmap.set (S sl ofs ty) (rs (R src)) (undef_regs (destroyed_by_setstack ty) rs) ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lsetstack src sl ofs ty :: bb) rs retty) m
        (LTL_Block s f sp bb rs' retty) m
  | ltl_effstep_Lstore: forall s f sp chunk addr args src bb rs m a rs' m' retty,
      eval_addressing g sp addr (reglist rs args) = Some a ->
      Mem.storev chunk m a (rs (R src)) = Some m' ->
      rs' = undef_regs (destroyed_by_store chunk addr) rs ->
      ltl_effstep g (StoreEffect a (encode_val chunk (rs (R src))))
        (LTL_Block s f sp (Lstore chunk addr args src :: bb) rs retty) m
        (LTL_Block s f sp bb rs' retty) m'
  | ltl_effstep_Lcall: forall s f sp sig ros bb rs m fd retty,
      find_function g ros rs = Some fd ->
      funsig fd = sig ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lcall sig ros :: bb) rs retty) m
        (LTL_Callstate (Stackframe f sp rs bb :: s) fd rs retty) m
  | ltl_effstep_Ltailcall: forall s f sp sig ros bb rs m fd rs' m' retty,
      rs' = return_regs (parent_locset s) rs ->
      find_function g ros rs' = Some fd ->
      funsig fd = sig ->
      Mem.free m sp 0 f.(fn_stacksize) = Some m' ->
      ltl_effstep g (FreeEffect m 0 (f.(fn_stacksize)) sp) 
        (LTL_Block s f (Vptr sp Int.zero) (Ltailcall sig ros :: bb) rs retty) m
        (LTL_Callstate s fd rs' retty) m'
  | ltl_effstep_Lbuiltin: forall s f sp ef args res bb rs m t vl rs' m' retty,
      external_call' ef g (reglist rs args) m t vl m' ->
      ~observableEF hf ef ->
      rs' = Locmap.setlist (map R res) vl (undef_regs (destroyed_by_builtin ef) rs) ->
      ltl_effstep g (BuiltinEffect g ef (decode_longs (sig_args (ef_sig ef)) (reglist rs args)) m)
         (LTL_Block s f sp (Lbuiltin ef args res :: bb) rs retty) m
         (LTL_Block s f sp bb rs' retty) m'

(* annotations are observable, so now handled by atExternal
  | ltl_effstep_Lannot: forall s f sp ef args bb rs m t vl m',
      external_call' ef g (map rs args) m t vl m' ->
      ltl_effstep g (BuiltinEffect g (ef_sig ef) (decode_longs (sig_args (ef_sig ef)) (map rs args)) m)
         (LTL_Block s f sp (Lannot ef args :: bb) rs) m
         (LTL_Block s f sp bb rs) m'
*)
  | ltl_effstep_Lbranch: forall s f sp pc bb rs m retty,
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lbranch pc :: bb) rs retty) m
        (LTL_State s f sp pc rs retty) m
  | ltl_effstep_Lcond: forall s f sp cond args pc1 pc2 bb rs b pc rs' m retty,
      eval_condition cond (reglist rs args) m = Some b ->
      pc = (if b then pc1 else pc2) ->
      rs' = undef_regs (destroyed_by_cond cond) rs ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Lcond cond args pc1 pc2 :: bb) rs retty) m
        (LTL_State s f sp pc rs' retty) m
  | ltl_effstep_Ljumptable: forall s f sp arg tbl bb rs m n pc rs' retty,
      rs (R arg) = Vint n ->
      list_nth_z tbl (Int.unsigned n) = Some pc ->
      rs' = undef_regs (destroyed_by_jumptable) rs ->
      ltl_effstep g EmptyEffect (LTL_Block s f sp (Ljumptable arg tbl :: bb) rs retty) m
        (LTL_State s f sp pc rs' retty) m
  | ltl_effstep_Lreturn: forall s f sp bb rs m m' retty,
      Mem.free m sp 0 f.(fn_stacksize) = Some m' ->
      ltl_effstep g (FreeEffect m 0 (f.(fn_stacksize)) sp)
        (LTL_Block s f (Vptr sp Int.zero) (Lreturn :: bb) rs retty) m
        (LTL_Returnstate s (sig_res (fn_sig f)) (return_regs (parent_locset s) rs) retty) m'
  | ltl_effstep_function_internal: forall s f rs m m' sp rs' retty,
      Mem.alloc m 0 f.(fn_stacksize) = (m', sp) ->
      rs' = undef_regs destroyed_at_function_entry (call_regs rs) ->
      ltl_effstep g EmptyEffect 
        (LTL_Callstate s (Internal f) rs retty) m
        (LTL_State s f (Vptr sp Int.zero) f.(fn_entrypoint) rs' retty) m'

  | ltl_effstep_function_external: forall s ef t args res rs m rs' m' retty
      (OBS: EFisHelper hf ef),
      args = map rs (loc_arguments (ef_sig ef)) ->
      external_call' ef g args m t res m' ->
      rs' = Locmap.setlist (map R (loc_result (ef_sig ef))) res rs ->
      ltl_effstep g (BuiltinEffect g ef args m)
          (LTL_Callstate s (External ef) rs retty) m
          (LTL_Returnstate s (sig_res (ef_sig ef)) rs' retty) m'

  | ltl_effstep_return: forall f sp rs1 bb s retty rs m retty0,
      ltl_effstep g EmptyEffect 
        (LTL_Returnstate (Stackframe f sp rs1 bb :: s) retty rs retty0) m
        (LTL_Block s f sp bb rs retty0) m.

Lemma ltlstep_effax1: forall (M : block -> Z -> bool) g c m c' m',
      ltl_effstep g M c m c' m' ->
      (corestep (LTL_coop_sem hf) g c m c' m' /\
       Mem.unchanged_on (fun (b : block) (ofs : Z) => M b ofs = false) m m').
Proof. 
intros.
  induction H.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         eapply StoreEffect_Storev; eassumption. 
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         eapply FreeEffect_free; eassumption.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         inv H.
         eapply BuiltinEffect_unchOn; eassumption.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         eapply FreeEffect_free; eassumption. 
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         eapply Mem.alloc_unchanged_on; eassumption.
  split. unfold corestep, coopsem; simpl. 
         eapply ltl_exec_function_external; eassumption.
         inv H0.
       exploit @BuiltinEffect_unchOn. 
         eapply EFhelpers; eassumption.
         eapply H2. 
       unfold BuiltinEffect; simpl.
         destruct ef; simpl; trivial; contradiction.
  split. unfold corestep, coopsem; simpl. econstructor; eassumption.
         apply Mem.unchanged_on_refl.
Qed.

Lemma ltlstep_effax2: forall  g c m c' m',
      corestep (LTL_coop_sem hf) g c m c' m' ->
      exists M, ltl_effstep g M c m c' m'.
Proof.
intros. unfold corestep, coopsem in H; simpl in H.
  inv H.
    eexists. eapply ltl_effstep_start_block; eassumption.
    eexists. eapply ltl_effstep_Lop; try eassumption; trivial.
    eexists. eapply ltl_effstep_Lload; try eassumption; trivial.
    eexists. eapply ltl_effstep_Lgetstack; try eassumption; trivial.
    eexists. eapply ltl_effstep_Lsetstack; try eassumption; trivial. 
    eexists. eapply ltl_effstep_Lstore; try eassumption; trivial.
    eexists. eapply ltl_effstep_Lcall; try eassumption; trivial.  
    eexists. eapply ltl_effstep_Ltailcall; try eassumption; trivial. 
    eexists. eapply ltl_effstep_Lbuiltin; try eassumption; trivial. 
    eexists. eapply ltl_effstep_Lbranch; eassumption.
    eexists. eapply ltl_effstep_Lcond; try eassumption; trivial.
    eexists. eapply ltl_effstep_Ljumptable; try eassumption; trivial.
    eexists. eapply ltl_effstep_Lreturn; eassumption.
    eexists. eapply ltl_effstep_function_internal; try eassumption; trivial.
    eexists. eapply ltl_effstep_function_external; try eassumption; trivial.
    eexists. eapply ltl_effstep_return.
Qed.

Lemma ltl_effstep_valid: forall (M : block -> Z -> bool) g c m c' m',
      ltl_effstep g M c m c' m' ->
       forall b z, M b z = true -> Mem.valid_block m b.
Proof.
intros.
  induction H; try (solve [inv H0]).

  apply StoreEffectD in H0. destruct H0 as [ofs [VADDR ARITH]]; subst.
  inv H1. apply Mem.store_valid_access_3 in H2.
  eapply Mem.valid_access_valid_block.
  eapply Mem.valid_access_implies; try eassumption. constructor.

  eapply FreeEffect_validblock; eassumption.
  eapply BuiltinEffect_valid_block; eassumption.
  eapply FreeEffect_validblock; eassumption.
  eapply BuiltinEffect_valid_block; eassumption.
Qed.

Program Definition LTL_eff_sem : 
  @EffectSem genv LTL_core.
eapply Build_EffectSem with (sem := LTL_coop_sem hf)(effstep:=ltl_effstep).
apply ltlstep_effax1.
apply ltlstep_effax2.
apply ltl_effstep_valid.
Defined.

End LTL_EFF.