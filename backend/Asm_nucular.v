(*Require Import compcert. Import CompcertAll.*) 
Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Locations.
Require Import Stacklayout.
Require Import Conventions.

Require Import val_casted.
Require Import BuiltinEffects.
Require Import load_frame.

Require Import core_semantics.
Require Import core_semantics_lemmas.
Require Import mem_wd.
Require Import mem_lemmas.
Require Import reach.
Require Import nucular_semantics.

(*LENB: We don't import CompCert's original Asm.v, but the modified one*)
Require Import AsmEFF.
Require Import Asm_coop.  
Notation SP := ESP (only parsing).

Notation "a # b" := (a b) (at level 1, only parsing).
Notation "a # b <- c" := (Pregmap.set b c a) (at level 1, b at next level).

Definition regmap_valid m (rs: regset):= forall r, val_valid (rs r) m.

Definition loader_valid m (lf: load_frame) := 
   match lf with mk_load_frame b oty => Mem.valid_block m b end. 

Definition vals_valid m vals:= Forall (fun v => val_valid v m) vals.

Lemma vals_valid_fwd m m' vals:vals_valid m vals -> 
      mem_forward m m' -> vals_valid m' vals.  
Proof. intros.
induction vals; simpl; intros; econstructor; eauto.
inv H. 
  eapply  Nuke_sem.val_valid_fwd; try eassumption. 
inv H. apply IHvals. apply H4.
Qed. 

Lemma vals_valid_getblocks: forall m vals,
   vals_valid m vals <->
   (forall b, getBlocks vals b = true -> Mem.valid_block m b).
Proof. intros.
induction vals; simpl; split; intros.
  rewrite getBlocks_char in H0. destruct H0. inv H0.
  constructor.
inv H.
  rewrite getBlocks_char in H0. destruct H0.
  destruct H. subst. apply H3.
  eapply IHvals. apply H4. rewrite getBlocks_char. exists x; trivial.
constructor.
  destruct a; simpl; trivial.
  apply H. rewrite getBlocks_char. exists i; left; trivial.
apply IHvals. intros. apply H. rewrite getBlocks_char.
  rewrite getBlocks_char in H0. destruct H0. exists x; right; trivial.
Qed.

Lemma decode_longs_getBlocks: forall tys vals b
      (GB: getBlocks (decode_longs tys vals) b = true),
      getBlocks vals b = true.
Proof. intros. 
  rewrite getBlocks_char.
  rewrite getBlocks_char in GB. destruct GB. exists x.
  generalize dependent vals.
  induction tys; intros.
     destruct vals; simpl in *; contradiction. 
  destruct vals; simpl in *. 
     destruct a; inv H. 
  destruct a. 
    destruct H. left; trivial. 
      apply IHtys in H; right; trivial.
    destruct H. left; trivial. 
      apply IHtys in H; right; trivial.
    destruct vals; inv H.
    unfold Val.longofwords in H0. destruct v; inv H0.
       destruct v0; inv H1.
      apply IHtys in H0. right. right; trivial.
    destruct H. left; trivial.
      apply IHtys in H. right; trivial.
Qed.      

Lemma vals_valid_decode m: forall tys vals,
      vals_valid m vals -> 
      vals_valid m (decode_longs tys vals).
Proof. intros. 
  rewrite vals_valid_getblocks in H.
  rewrite vals_valid_getblocks.
  intros. apply H. clear H. 
  eapply decode_longs_getBlocks; eassumption.
Qed.

Lemma regmap_valid_nextinstr m rs:
   regmap_valid m rs -> regmap_valid m (nextinstr rs).
Proof. intros.
  red; intros. 
  remember (nextinstr rs r) as v. 
  destruct v; simpl; trivial.
  unfold nextinstr in Heqv. 
  specialize (H r).
  destruct (Pregmap.elt_eq r PC). 
    subst. rewrite Pregmap.gss in Heqv. 
    destruct (rs PC); inv Heqv. apply H.
  rewrite Pregmap.gso in Heqv; trivial. 
    rewrite <- Heqv in H; apply H.
Qed. 
Lemma regmap_valid_assign m rs rd: regmap_valid m rs ->
      forall v, val_valid v m -> 
      regmap_valid m rs # rd <- v.
Proof. intros.
  red; intros. 
  remember (rs # rd <- v r) as u. 
  destruct u; simpl; trivial.
  destruct (Pregmap.elt_eq r rd). 
    subst. rewrite Pregmap.gss in Hequ. 
    subst v. apply H0. 
  rewrite Pregmap.gso in Hequ; trivial. 
    specialize (H r).
    rewrite <- Hequ in H; apply H.
Qed.

Lemma undef_regsD: forall L rs v r,
  undef_regs L rs r = v -> v<> Vundef -> ~ In r L /\ rs r = v.
Proof. 
induction L; simpl; intros. split; trivial. auto.
apply IHL in H; trivial. destruct H. unfold Pregmap.set in H1.
  destruct (PregEq.eq r a). 
    subst. congruence.
  split; trivial. intros N. destruct N; subst. congruence.
  apply (H H2).
Qed.

Lemma regmap_valid_assign_reg m rs rd r: regmap_valid m rs -> 
      regmap_valid m rs # rd <- (rs r).
Proof. intros. eapply regmap_valid_assign; eauto. Qed.   

Lemma regmap_valid_undef_regs m: forall L rs,
      regmap_valid m rs -> 
      regmap_valid m (undef_regs L rs).
Proof. intros L. 
destruct L; simpl; intros; trivial. 
red; intros.
  remember (undef_regs L rs # p <- Vundef r) as u. 
  destruct u; simpl; trivial.
  apply eq_sym in Hequ. apply undef_regsD in Hequ.
  destruct Hequ.
    destruct (PregEq.eq r p). 
      subst. rewrite Pregmap.gss in H1. inv H1.
    rewrite Pregmap.gso in H1; trivial. 
      specialize (H r). rewrite H1 in H. apply H.
  intros N; discriminate.
Qed. 

(*Lemma regmap_valid_undef_regs m: forall L rs rd v,
      regmap_valid m rs -> val_valid v m -> 
      regmap_valid m (undef_regs L rs # rd <- v).
Proof. intros L. 
destruct L; simpl; intros. 
  apply regmap_valid_assign; eauto.
red; intros.
  remember (undef_regs L (rs # rd <- v) # p <- Vundef r)
     as u. 
  destruct u; simpl; trivial.
  apply eq_sym in Hequ. apply undef_regsD in Hequ.
  destruct Hequ.
    destruct (PregEq.eq r p). 
      subst. rewrite Pregmap.gss in H2. inv H2.
    rewrite Pregmap.gso in H2; trivial. 
    destruct (PregEq.eq r rd). 
      subst. rewrite Pregmap.gss in H2. subst v; apply H0.
    rewrite Pregmap.gso in H2; trivial. 
      specialize (H r). rewrite H2 in H. apply H.
  intros N; discriminate.
Qed. 
*)  

Lemma loader_valid_forward m m' lf: loader_valid m lf ->
      mem_forward m m' -> loader_valid m' lf.
Proof. intros.
  destruct lf; simpl in *.
  apply H0; eassumption.
Qed.

Lemma regmap_valid_forward m m' rs: regmap_valid m rs ->
      mem_forward m m' -> regmap_valid m' rs.
Proof. intros. red; intros. specialize (H r).
  destruct (rs r); simpl; trivial.
  apply H0; eassumption.
Qed.

Lemma val_valid_sub m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.sub u v) m.
Proof. intros. unfold Val.sub.
  destruct u; destruct v; simpl; trivial.
  destruct (eq_block b b0); simpl; trivial.
Qed.

Lemma val_valid_add m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.add u v) m.
Proof. intros. unfold Val.add.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_mul m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.mul u v) m.
Proof. intros. unfold Val.mul.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_mulhs m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.mulhs u v) m.
Proof. intros. unfold Val.mulhs.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_mulhu m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.mulhu u v) m.
Proof. intros. unfold Val.mulhu.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_and m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.and u v) m.
Proof. intros. unfold Val.and.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_or m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.or u v) m.
Proof. intros. unfold Val.or.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_xor m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.xor u v) m.
Proof. intros. unfold Val.xor.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_shl m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.shl u v) m.
Proof. intros. unfold Val.shl.
  destruct u; destruct v; simpl; trivial.
  destruct (Int.ltu i0 Int.iwordsize); simpl; trivial. 
Qed.

Lemma val_valid_shr m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.shr u v) m.
Proof. intros. unfold Val.shr.
  destruct u; destruct v; simpl; trivial.
  destruct (Int.ltu i0 Int.iwordsize); simpl; trivial.
Qed.

Lemma val_valid_shru m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.shru u v) m.
Proof. intros. unfold Val.shru.
  destruct u; destruct v; simpl; trivial.
  destruct (Int.ltu i0 Int.iwordsize); simpl; trivial.
Qed.

Lemma val_valid_ror m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.ror u v) m.
Proof. intros. unfold Val.ror.
  destruct u; destruct v; simpl; trivial.
  destruct (Int.ltu i0 Int.iwordsize); simpl; trivial.
Qed.

Lemma val_valid_addf m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.addf u v) m.
Proof. intros. unfold Val.addf.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_subf m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.subf u v) m.
Proof. intros. unfold Val.subf.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_mulf m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.mulf u v) m.
Proof. intros. unfold Val.mulf.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_divf m u v: val_valid u m -> val_valid v m ->
      val_valid (Val.divf u v) m.
Proof. intros. unfold Val.divf.
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma val_valid_negf m u: val_valid u m ->
      val_valid (Val.negf u) m.
Proof. intros. unfold Val.negf.
  destruct u; simpl; trivial.
Qed.

Lemma val_valid_absf m u: val_valid u m ->
      val_valid (Val.absf u) m.
Proof. intros. unfold Val.absf.
  destruct u; simpl; trivial.
Qed.

Lemma val_valid_cmpu CMP m u v:
    val_valid (Val.cmpu (Mem.valid_pointer m) CMP u v) m.
Proof. intros.
      unfold Val.cmpu, Val.of_optbool, Val.cmpu_bool.
      destruct u; destruct v; simpl; trivial. 
      destruct (Int.cmpu CMP i i0); simpl; trivial. 
      destruct (Int.eq i Int.zero); simpl; trivial. 
      destruct (Val.cmp_different_blocks CMP); simpl; trivial. 
      destruct b0; simpl; trivial.
      destruct (Int.eq i0 Int.zero); simpl; trivial. 
      destruct (Val.cmp_different_blocks CMP); simpl; trivial. 
      destruct b0; simpl; trivial.
      destruct (eq_block b b0); simpl; trivial. 
      destruct ((Mem.valid_pointer m b (Int.unsigned i)
            || Mem.valid_pointer m b (Int.unsigned i - 1)) &&
           (Mem.valid_pointer m b0 (Int.unsigned i0)
            || Mem.valid_pointer m b0 (Int.unsigned i0 - 1)));
       simpl; trivial.
       destruct (Int.cmpu CMP i i0); simpl; trivial. 
      destruct (Mem.valid_pointer m b (Int.unsigned i) &&
           Mem.valid_pointer m b0 (Int.unsigned i0)); simpl; trivial.
      destruct (Val.cmp_different_blocks CMP); simpl; trivial. 
      destruct b1; simpl; trivial.
Qed. 
Lemma val_valid_negative m u: val_valid (Val.negative u) m. 
Proof. intros.  unfold Val.negative.
  destruct u; simpl; trivial.
Qed.
Lemma val_valid_sub_overflow m u v : 
      val_valid (Val.sub_overflow u v) m. 
Proof. intros. unfold Val.sub_overflow. 
  destruct u; destruct v; simpl; trivial.
Qed.

Lemma eval_addrmode_valid ge m a rs b ofs: forall
     (GENV: valid_genv ge m)
     (REGS : regmap_valid m rs)
     (EA: eval_addrmode ge a rs = Vptr b ofs),
   Mem.valid_block m b.
Proof. intros.
  unfold eval_addrmode, symbol_offset in EA.
  destruct a; simpl in *.
  destruct base; simpl; trivial. 
  { assert (HH1:= REGS i).
    unfold Val.add in EA.
    destruct (rs i); simpl in *; try discriminate.
      destruct ofs0; try discriminate. 
      { destruct p.
        remember (if Int.eq i2 Int.one then rs i1
           else Val.mul (rs i1) (Vint i2)) as q;
        destruct q; simpl in *; inv EA. 
          destruct const; inv H0.
          destruct p.
          remember (Genv.find_symbol ge i4) as u. 
          destruct u; inv H1. destruct GENV as [GE ?].
          apply eq_sym in Hequ. apply (GE _ _ Hequ).
        destruct const; inv H0.
          unfold Val.mul in Heqq.
          destruct (Int.eq i2 Int.one).
            specialize (REGS i1); rewrite <- Heqq in REGS.
            apply REGS.
          destruct (rs i1); inv Heqq.
       destruct p.
         remember (Genv.find_symbol ge i4) as u. 
         destruct u; inv H1. }

      { unfold Vzero in EA; simpl in *.
         destruct const; try discriminate. destruct p.
         remember (Genv.find_symbol ge i1) as u. 
         destruct u; inv EA. destruct GENV as [GE ?].
         apply eq_sym in Hequ. apply (GE _ _ Hequ). }
      { destruct ofs0; simpl in *. 
         destruct p.
         remember (if Int.eq i2 Int.one then rs i1 
                  else Val.mul (rs i1) (Vint i2)) as q.
         destruct q; inv EA; simpl in *; trivial. 
         destruct const; inv H0; trivial. 
             destruct p. 
             remember (Genv.find_symbol ge i4) as u. 
             destruct u; inv H1.   
         destruct const; inv H0; trivial. 
             destruct p. 
             remember (Genv.find_symbol ge i4) as u. 
             destruct u; inv H1. 
         destruct const; inv EA; trivial.
           destruct p. 
           remember (Genv.find_symbol ge i1) as u. 
           destruct u; inv H0.  } }

 { unfold Val.add, Vzero in EA; simpl in *.
   destruct ofs0; inv EA.
     destruct p.
     remember (if Int.eq i0 Int.one then rs i 
            else Val.mul (rs i) (Vint i0)) as q.
     destruct q; inv H0.
     destruct const; inv H1; trivial. 
     { destruct p. 
       remember (Genv.find_symbol ge i2) as u. 
       destruct u; inv H0. destruct GENV as [GE ?].
         apply eq_sym in Hequ. apply (GE _ _ Hequ). }
     { destruct const; inv H1; trivial. 
       unfold Val.mul in Heqq. 
       destruct (Int.eq i0 Int.one); inv Heqq.
         specialize (REGS i); rewrite <- H0 in REGS.
            apply REGS.
          destruct (rs i); inv H0.
       destruct p.
       remember (Genv.find_symbol ge i2) as u. 
       destruct u; inv H0. } 
     destruct const; inv H0; trivial. 
     { destruct p. 
       remember (Genv.find_symbol ge i) as u. 
       destruct u; inv H1. destruct GENV as [GE ?].
         apply eq_sym in Hequ. apply (GE _ _ Hequ). } } 
Qed. 

Lemma extcall_arguments_valid rs m: regmap_valid m rs ->
       mem_wd m -> forall sg args,
       extcall_arguments rs m sg args -> vals_valid m args.
Proof. 
unfold extcall_arguments. intros.
remember (loc_arguments sg) as tys. clear Heqtys.
induction H1; simpl; intros; constructor; eauto. 
inv H1; simpl in *.
  apply H.
unfold Val.add in H4. 
  destruct (rs ESP); simpl in *; try discriminate. 
  apply mem_wd_load in H4; trivial.
Qed.

Lemma store_args_rec_fwd: forall tys args m stk mm n,
       store_args_rec m stk n args tys = Some mm ->
      mem_forward m mm.
Proof. unfold store_args. intros tys.
induction tys; destruct args; intros; inv H.
  apply mem_forward_refl. 
destruct a.
  remember (store_stack m (Vptr stk Int.zero) Tint
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
    apply IHtys in H0; clear IHtys.
    unfold store_stack in Heqq; simpl in *.
    apply store_forward in Heqq.
    eapply mem_forward_trans; eassumption.
  remember (store_stack m (Vptr stk Int.zero) Tfloat
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
    apply IHtys in H0; clear IHtys.
    unfold store_stack in Heqq; simpl in *.
    apply store_forward in Heqq.
    eapply mem_forward_trans; eassumption.
  destruct v; try discriminate.
  remember (store_stack m (Vptr stk Int.zero) Tint
           (Int.repr
              match n + 1 with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) (Vint (Int64.hiword i)))
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
  remember (store_stack m0 (Vptr stk Int.zero) Tint
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) (Vint (Int64.loword i)))
    as w; destruct w; inv H0; apply eq_sym in Heqw. 
    apply IHtys in H1; clear IHtys.
    unfold store_stack in *; simpl in *.
    apply store_forward in Heqq.
    apply store_forward in Heqw.
    eapply mem_forward_trans. eassumption.
    eapply mem_forward_trans; eassumption.
  remember (store_stack m (Vptr stk Int.zero) Tsingle
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
    apply IHtys in H0; clear IHtys.
    unfold store_stack in Heqq; simpl in *.
    apply store_forward in Heqq.
    eapply mem_forward_trans; eassumption.
Qed.

Lemma store_args_fwd: forall tys args m stk mm,
      store_args m stk args tys = Some mm ->
      mem_forward m mm.
Proof. unfold store_args. intros. 
  eapply store_args_rec_fwd; eauto. 
Qed. 

Lemma store_args_rec_wd: forall tys args m stk mm n (WD: mem_wd m)
      (ARGS: vals_valid m args), 
      store_args_rec m stk n args tys = Some mm -> mem_wd mm.
Proof. unfold store_args. intros tys.
induction tys; destruct args; intros; inv H; trivial.
destruct a.
  remember (store_stack m (Vptr stk Int.zero) Tint
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq.
    inv ARGS. 
    unfold store_stack in Heqq; simpl in *.
    apply IHtys in H0; clear IHtys; trivial.
      eapply mem_wd_store; eauto. 
      apply store_forward in Heqq.
        eapply vals_valid_fwd; eassumption.
  remember (store_stack m (Vptr stk Int.zero) Tfloat
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
    inv ARGS.
    unfold store_stack in Heqq; simpl in *.
    apply IHtys in H0; clear IHtys; trivial.
      eapply mem_wd_store; eauto. 
      apply store_forward in Heqq.
        eapply vals_valid_fwd; eassumption.
  destruct v; try discriminate.
  remember (store_stack m (Vptr stk Int.zero) Tint
           (Int.repr
              match n + 1 with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) (Vint (Int64.hiword i)))
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
  remember (store_stack m0 (Vptr stk Int.zero) Tint
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) (Vint (Int64.loword i)))
    as w; destruct w; inv H0; apply eq_sym in Heqw. 
    inv ARGS. 
    unfold store_stack in *; simpl in *.
    apply IHtys in H1; clear IHtys; trivial.
      eapply mem_wd_store; try eapply Heqw. 
      eapply mem_wd_store; eauto. 
       simpl. trivial.
      apply store_forward in Heqq.
      apply store_forward in Heqw. 
      eapply vals_valid_fwd; try eapply Heqw.
      eapply vals_valid_fwd; eassumption.
  remember (store_stack m (Vptr stk Int.zero) Tsingle
           (Int.repr
              match n with
              | 0 => 0
              | Z.pos y' => Z.pos y'~0~0
              | Z.neg y' => Z.neg y'~0~0
              end) v)
    as q; destruct q; inv H1; apply eq_sym in Heqq. 
    inv ARGS.
    unfold store_stack in Heqq; simpl in *.
    apply IHtys in H0; clear IHtys; trivial.
      eapply mem_wd_store; eauto. 
      apply store_forward in Heqq.
        eapply vals_valid_fwd; eassumption.
Qed.

Lemma store_args_wd: forall tys args m stk mm,
      store_args m stk args tys = Some mm -> mem_wd m ->
      vals_valid m args -> mem_wd mm.
Proof. unfold store_args; simpl; intros.
eapply store_args_rec_wd; eauto.
Qed.

Lemma mem_wd_nonobservables: forall {F V: Type} (ge:Genv.t F V) 
      hf m m' ef t args v (OBS: ~ observableEF hf ef)
      (EC: external_call ef ge args m t v m') (WD: mem_wd m),
      mem_wd m'.
Proof. intros.
       destruct ef; simpl in OBS; try solve [elim OBS; trivial];
        inv EC; trivial.
       eapply mem_wd_store; try eapply H0. 
                eapply mem_wd_alloc; eassumption.
                simpl; trivial.
       eapply mem_wd_free; eassumption.
       eapply mem_wd_storebytes; try eassumption.
                eapply loadbytes_valid; eassumption. 
Qed.

Lemma regmap_valid_set_regs m: forall res L rs,
   regmap_valid m rs -> vals_valid m L ->
   regmap_valid m (set_regs res L rs).
Proof. intros res.
induction res; simpl; intros. trivial.
destruct L; simpl; trivial. 
  inv H0. simpl.
  eapply IHres; trivial.
  apply regmap_valid_assign; trivial. 
Qed. 

Lemma vals_valid_i64helpers {F V: Type} (ge: Genv.t F V)
      hf m vals t v m' name sg: forall   
      ( EC : extcall_io_sem name sg ge vals m t v m')
      (i : I64Helpers.is_I64_helper hf name sg),
   vals_valid m' (encode_long (sig_res sg) v).
Proof. intros.
  inv i; inv EC; simpl in *.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
  unfold I64Helpers.sig_l_f, proj_sig_res in H0. simpl in H0.
    inv H0. constructor; constructor; simpl; trivial.
  unfold I64Helpers.sig_l_f, proj_sig_res in H0. simpl in H0.
    inv H0. constructor; constructor; simpl; trivial.
  unfold I64Helpers.sig_l_s, proj_sig_res in H0. simpl in H0.
    inv H0. constructor; constructor; simpl; trivial.
  unfold I64Helpers.sig_l_s, proj_sig_res in H0. simpl in H0.
    inv H0. constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
   unfold Val.hiword, Val.loword. 
     destruct v; constructor; constructor; simpl; trivial.
Qed.

Lemma vals_valid_nonobservables {F V: Type} (ge: Genv.t F V)
      hf m ef vals t v m': forall    
      (OBS: ~ observableEF hf ef)
      (EC: external_call ef ge vals m t v m'),
      vals_valid m' (encode_long (sig_res (ef_sig ef)) v).
Proof. intros. 
destruct ef; simpl in *; try solve [elim OBS; trivial].
destruct (I64Helpers.is_I64_helper_dec hf name sg);
    try solve [elim (OBS n)]; clear OBS.
  eapply vals_valid_i64helpers; eassumption.
destruct (I64Helpers.is_I64_helper_dec hf name sg);
    try solve [elim (OBS n)]; clear OBS.
  eapply vals_valid_i64helpers; eassumption.
inv EC. apply Mem.valid_new_block in H. 
          constructor; simpl. eapply store_forward; eassumption.
          constructor.
inv EC. constructor; simpl; trivial.
inv EC. constructor; simpl; trivial. 
Qed.

Section ASM_NUC.
Variable hf : I64Helpers.helper_functions.

(*Variable ge: genv.*)
Print load_frame.
Definition Inv (c: state) (m:mem): Prop :=
  mem_wd m /\ (*valid_genv ge m /\*)
  match c with
  | State rs lf => regmap_valid m rs /\ loader_valid m lf
  | Asm_CallstateIn f args tys oty =>
       Mem.valid_block m f /\ vals_valid m args 
  | Asm_CallstateOut _ vals rs lf =>
       regmap_valid m rs /\ loader_valid m lf /\ vals_valid m vals
  end. 

Theorem Asm_is_nuc: Nuke_sem.t (Asm_core_sem hf).
Proof.
econstructor. instantiate (1:= Inv). 
{ intros.
   unfold Asm_core_sem in H2. simpl in *.
   unfold Asm_initial_core in H2; simpl in *.
   destruct v; try discriminate. 
   destruct (Int.eq_dec i Int.zero); try discriminate. 
   remember (Genv.find_funct_ptr ge b) as q. 
   destruct q; try discriminate. 
   destruct f; try discriminate.
   remember ( val_has_type_list_func args (sig_args (funsig (Internal f))) &&
           vals_defined args &&zlt
             match
               match Zlength args with
               | 0 => 0
               | Z.pos y' => Z.pos y'~0
               | Z.neg y' => Z.neg y'~0
               end
             with
             | 0 => 0
             | Z.pos y' => Z.pos y'~0~0
             | Z.neg y' => Z.neg y'~0~0
             end Int.max_unsigned) as w. 
   destruct w; try discriminate.
   inv H2; simpl.
   split. trivial. 
   split. unfold valid_genv in H0. 
     apply eq_sym in Heqq.
       admit. (* eapply H0. clear Heqw. instantiate (1:=f). specialize @Genv.find_funct_ptr_inversion. in Heqq.*)
   apply H. }
{ intros ? ? ? ? ? CS GENV INV.
  inv CS; simpl in *.
    destruct INV as [MEM [REGS LF]]. 
    destruct i; simpl in *; inv H2.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign_reg; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs. 
      apply regmap_valid_assign; trivial. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.
      unfold symbol_offset. 
      remember (Genv.find_symbol ge id) as v. 
      destruct v; simpl in *; trivial. 
      apply eq_sym in Heqv. destruct GENV as [GE _].
        apply (GE _ _ Heqv).

   unfold exec_load in H4.
   remember (Mem.loadv Mint32 m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

   unfold exec_store in H4.
   remember (Mem.storev Mint32 m (eval_addrmode ge a rs) (rs rs0)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      red; intros. specialize (REGS r).
      eapply  Nuke_sem.val_valid_fwd; eassumption.
    eapply loader_valid_forward; eassumption.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; trivial. simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mfloat64al32 m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

   unfold exec_store in H4.
   remember ( Mem.storev Mfloat64al32 m (eval_addrmode ge a rs) (rs r1)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      red; intros. specialize (REGS r).
      eapply  Nuke_sem.val_valid_fwd; eassumption.
    eapply loader_valid_forward; eassumption.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; trivial. simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mfloat64al32 m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; trivial. simpl; trivial.
      apply regmap_valid_assign; trivial. simpl; trivial.

   unfold exec_store in H4.
   remember (Mem.storev Mfloat64al32 m (eval_addrmode ge a rs) (rs ST0)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply regmap_valid_forward; eassumption.
    eapply loader_valid_forward; eassumption.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.

   unfold exec_store in H4.
   remember ( Mem.storev Mint8unsigned m (eval_addrmode ge a rs) (rs rs0)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      eapply regmap_valid_forward; eassumption.
    eapply loader_valid_forward; eassumption.

   unfold exec_store in H4.
   remember (Mem.storev Mint16unsigned m (eval_addrmode ge a rs) (rs rs0)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      eapply regmap_valid_forward; eassumption.
    eapply loader_valid_forward; eassumption.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.zero_ext.
      destruct (rs rs0) in *; simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mint8unsigned m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.zero_ext.
      destruct (rs rs0) in *; simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mint8signed m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.zero_ext.
      destruct (rs rs0) in *; simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mint16unsigned m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.sign_ext.
      destruct (rs rs0) in *; simpl; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mint16signed m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

   unfold exec_load in H4.
   remember (Mem.loadv Mfloat32 m (eval_addrmode ge a rs)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply mem_wd_load in H3; trivial.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; trivial.

    split; trivial. 
    split; trivial.
    apply regmap_valid_nextinstr.  
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.singleoffloat.
      destruct (rs r1) in *; simpl; trivial.

   unfold exec_store in H4.
   remember (Mem.storev Mfloat32 m (eval_addrmode ge a rs) (rs r1)) as q.
   destruct q; inv H4; apply eq_sym in Heqq.
   remember (eval_addrmode ge a rs) as u.
   destruct u; inv Heqq.
   split. eapply mem_wd_store; try eassumption.
          eapply REGS.
   apply store_forward in H3.
   split.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial. 
      apply regmap_valid_assign; simpl; trivial.
      eapply regmap_valid_forward; eassumption.
    eapply loader_valid_forward; eassumption.
 
    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.maketotal, Val.intoffloat.
      destruct (rs r1); simpl; trivial.
      unfold option_map. destruct (Float.intoffloat); simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.maketotal, Val.floatofint.
      destruct (rs r1); simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      remember (eval_addrmode ge a rs) as q.
      destruct q; simpl; trivial; apply eq_sym in Heqq.
      eapply eval_addrmode_valid; eassumption.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.neg.
      destruct (rs rd); simpl; trivial. 

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_sub; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_mul; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_mul; eauto.
      simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_mul; eauto.
      eapply val_valid_mulhs; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_mul; eauto.
      eapply val_valid_mulhu; eauto.

    remember (Val.divu (rs EAX) (rs # EDX <- Vundef r1)) as q.
      destruct q; inv H4. 
    remember (Val.modu (rs EAX) (rs # EDX <- Vundef r1)) as w.
      destruct w; inv H3. 
    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.divu in Heqq.
      destruct (rs EAX); inv Heqq.
      unfold Pregmap.set in *. 
      destruct (PregEq.eq r1 EDX); inv H3. 
      destruct (rs r1); inv H4. 
      destruct (Int.eq i0 Int.zero); inv H3; simpl; trivial.
 
      unfold Val.modu in Heqw.
      destruct (rs EAX); inv Heqw.
      unfold Pregmap.set in *. 
      destruct (PregEq.eq r1 EDX); inv H3. 
      destruct (rs r1); inv H4. 
      destruct (Int.eq i0 Int.zero); inv H3; simpl; trivial. 

    remember (Val.divs (rs EAX) (rs # EDX <- Vundef r1)) as q.
      destruct q; inv H4. 
    remember (Val.mods (rs EAX) (rs # EDX <- Vundef r1)) as w.
      destruct w; inv H3. 
    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.divs in Heqq.
      destruct (rs EAX); inv Heqq.
      unfold Pregmap.set in *. 
      destruct (PregEq.eq r1 EDX); inv H3. 
      destruct (rs r1); inv H4. 
      destruct ( Int.eq i0 Int.zero
           || Int.eq i (Int.repr Int.min_signed) && Int.eq i0 Int.mone);
         inv H3; simpl; trivial.
 
      unfold Val.mods in Heqw.
      destruct (rs EAX); inv Heqw.
      unfold Pregmap.set in *. 
      destruct (PregEq.eq r1 EDX); inv H3. 
      destruct (rs r1); inv H4. 
      destruct (Int.eq i0 Int.zero
           || Int.eq i (Int.repr Int.min_signed) && Int.eq i0 Int.mone);
       inv H3; simpl; trivial. 

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_and; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_and; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_or; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_or; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_xor; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_xor; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shl; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shl; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shru; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shru; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shr; eauto.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_shr; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_or; eauto.
      eapply val_valid_shl; eauto. simpl; trivial.
      eapply val_valid_shru; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_ror; eauto. simpl; trivial.

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_negative; eauto.
      eapply val_valid_sub_overflow; eauto. 
  
    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_negative; eauto.
      eapply val_valid_sub_overflow; eauto.   

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_negative; eauto.
      eapply val_valid_sub_overflow; eauto.   
 

    split; trivial.  
    split; trivial.
    apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_cmpu; eauto.  
      eapply val_valid_negative; eauto.
      eapply val_valid_sub_overflow; eauto.   
 
   destruct (eval_testcond c rs). 
    destruct b0; inv H4.
      split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr. 
      apply regmap_valid_assign; simpl; trivial.
      split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr. trivial.
    inv H4.
      split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.of_optbool.
      remember (eval_testcond c rs) as w. 
      destruct w; simpl; trivial.
      destruct b0; simpl; trivial.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_addf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_subf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_mulf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_divf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_negf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_assign; simpl; trivial.
      apply val_valid_absf; eauto.

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      unfold compare_floats.
      destruct (rs r1);
        try solve [apply regmap_valid_undef_regs; trivial].
      destruct (rs r2);
        try solve [apply regmap_valid_undef_regs; trivial].
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      unfold Val.of_bool.
        destruct (negb (Float.cmp Cne f0 f1)); simpl; trivial. 
      unfold Val.of_bool.
        destruct (negb (Float.cmp Cge f0 f1)); simpl; trivial. 
      unfold Val.of_bool.
        destruct (negb
           (Float.cmp Ceq f0 f1 || Float.cmp Clt f0 f1 || Float.cmp Cgt f0 f1)); simpl; trivial. 

    split; trivial.  
      split; trivial.
      apply regmap_valid_nextinstr.
      apply regmap_valid_undef_regs; trivial.
      apply regmap_valid_assign; simpl; trivial.

    unfold goto_label in H4. 
      destruct (label_pos l 0 (fn_code f)); inv H4.
      remember (rs PC) as q;
      destruct q; inv H3. inv H.
      split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.
      specialize (REGS PC). rewrite<- Heqq in REGS; apply REGS.

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.
      remember (symbol_offset ge symb Int.zero) as q.
      destruct q; simpl; trivial.
      unfold  symbol_offset in Heqq.
      remember (Genv.find_symbol ge symb) as w. 
      destruct w; inv Heqq. apply eq_sym in Heqw.
      destruct GENV as [GE _]. apply (GE _ _ Heqw).

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.

    remember (eval_testcond c rs) as q.
      destruct q; inv H4. 
      destruct b0; inv H3. 
     
      unfold goto_label in H4.
      destruct (label_pos l 0 (fn_code f)); inv H4. 
      remember (rs PC) as w; destruct w; inv H3. 
      split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial. inv H. 
      specialize (REGS PC). rewrite <- Heqw in REGS; apply REGS.

      split; trivial.
      split; trivial.
      apply regmap_valid_nextinstr. trivial.

    remember (eval_testcond c1 rs) as q.
      destruct q; inv H4. 
      remember (eval_testcond c2 rs) as u.
      destruct u; inv H3. 
      destruct b0; inv H4. 
      destruct b1; inv H3. 
     
      unfold goto_label in H4.
      destruct (label_pos l 0 (fn_code f)); inv H4. 
      remember (rs PC) as w; destruct w; inv H3. 
      split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial. inv H. 
      specialize (REGS PC). rewrite <- Heqw in REGS; apply REGS.

      split; trivial.
      split; trivial.
      apply regmap_valid_nextinstr. trivial.
      split; trivial.
      split; trivial.
      apply regmap_valid_nextinstr. trivial.
      destruct b0; inv H4.

    remember (rs r) as q; destruct q; inv H4.
      destruct (list_nth_z tbl (Int.unsigned i)); inv H3.
      unfold goto_label in H4.
      destruct (label_pos l 0 (fn_code f)); inv H4. 
      remember (rs PC) as w; destruct w; inv H3. 
      split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial. inv H. 
      specialize (REGS PC). rewrite <- Heqw in REGS; apply REGS.

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      specialize (REGS PC). rewrite H in *; simpl in *. trivial. 
      unfold symbol_offset.
      remember (Genv.find_symbol ge symb) as w. 
      destruct w; simpl; trivial. apply eq_sym in Heqw.
      destruct GENV as [GE _]. apply (GE _ _ Heqw).

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.
      apply regmap_valid_assign; simpl; trivial.
      specialize (REGS PC). rewrite H in *; simpl in *. trivial. 

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.

    split; trivial.
      split; trivial.
      apply regmap_valid_assign; simpl; trivial.
      specialize (REGS PC). rewrite H in *; simpl in *. trivial. 

    remember (Mem.alloc m 0 sz) as dd. 
      destruct dd; apply eq_sym in Heqdd.
      remember (Mem.store Mint32 m0 b0 
                 (Int.unsigned (Int.add Int.zero ofs_link))
                (rs ESP)) as q.
       destruct q; inv H4; apply eq_sym in Heqq.
      remember (Mem.store Mint32 m1 b0
                (Int.unsigned (Int.add Int.zero ofs_ra))
                (rs RA)) as w.
       destruct w; inv H3; apply eq_sym in Heqw.
      split. eapply mem_wd_store; try eapply Heqw.  
             eapply mem_wd_store; try eapply Heqq.
             eapply mem_wd_alloc; eassumption. 
      specialize (REGS ESP). apply alloc_forward in Heqdd. 
           eapply Nuke_sem.val_valid_fwd; eassumption.
      specialize (REGS RA). apply alloc_forward in Heqdd.
          apply store_forward in Heqq.
           eapply Nuke_sem.val_valid_fwd; try eapply Heqq.
           eapply Nuke_sem.val_valid_fwd; eassumption.
      specialize (Mem.valid_new_block _ _ _ _ _ Heqdd); intros VB.
      apply alloc_forward in Heqdd.
          apply store_forward in Heqq.
          apply store_forward in Heqw. 
        split. 
          eapply regmap_valid_forward; try eapply Heqw.
          eapply regmap_valid_forward; try eapply Heqq.
          apply regmap_valid_assign; simpl; trivial.
          apply regmap_valid_assign; simpl; trivial.
          apply regmap_valid_assign; simpl; trivial.
          eapply regmap_valid_forward; try eapply Heqdd. assumption.
          eapply Nuke_sem.val_valid_fwd; try eapply Heqdd. apply REGS.
          eapply Nuke_sem.val_valid_fwd; try eapply Heqdd. 
          rewrite Pregmap.gso.         
          rewrite Pregmap.gso. specialize (REGS PC). 
            rewrite H in *; simpl in *; assumption.
           congruence. congruence.
        eapply loader_valid_forward; try eapply Heqw.
          eapply loader_valid_forward; try eapply Heqq.
          eapply loader_valid_forward; try apply Heqdd. assumption.

      remember (Mem.loadv Mint32 m (Val.add (rs ESP) (Vint ofs_ra)))
          as d; destruct d; inv H4; apply eq_sym in Heqd. 
      remember (Mem.loadv Mint32 m (Val.add (rs ESP) (Vint ofs_link)))
          as q; destruct q; inv H3; apply eq_sym in Heqq. 
        destruct (rs ESP); inv H4. simpl in *.
        remember (Mem.free m b0 0 sz) as w; 
          destruct w; inv H3; apply eq_sym in Heqw.

        split. eapply mem_wd_free; eassumption.
        apply free_forward in Heqw. 
        split.  
          eapply regmap_valid_forward; try eapply Heqw.
          apply regmap_valid_assign; simpl; trivial.
          apply regmap_valid_assign; simpl; trivial.
          apply regmap_valid_assign; simpl; trivial.
             eapply mem_wd_load; eassumption.
             eapply mem_wd_load; eassumption. 
          rewrite Pregmap.gso. rewrite Pregmap.gso. 
            specialize (REGS PC). 
            rewrite H in *; simpl in *; assumption.
           congruence. congruence.
          eapply loader_valid_forward; eassumption.
   destruct INV as [? [? ?]]. inv H2.
     split; simpl. eapply mem_wd_nonobservables; eassumption.
     split. 
       apply regmap_valid_nextinstr.
       apply regmap_valid_undef_regs; trivial.
       eapply regmap_valid_set_regs.
         apply regmap_valid_undef_regs; trivial.
         apply external_call_mem_forward in H7.
         eapply regmap_valid_forward; eassumption.
       eapply vals_valid_nonobservables; eassumption.
     apply external_call_mem_forward in H7.
      eapply loader_valid_forward; eassumption. 
   destruct INV as [? [? ?]].
     split; intuition. 
     eapply extcall_arguments_valid; eassumption.
 
   destruct INV as [? [? [? ?]]]. inv H1.
     apply EFhelpers in OBS. 
     split; simpl. eapply mem_wd_nonobservables; eassumption.
     split. 
       apply regmap_valid_assign.
       eapply regmap_valid_set_regs.
         apply external_call_mem_forward in H6.
         eapply regmap_valid_forward; eassumption.
       eapply vals_valid_nonobservables; eassumption.
       specialize (H3 RA).
       apply external_call_mem_forward in H6.
       eapply Nuke_sem.val_valid_fwd; eassumption.
     apply external_call_mem_forward in H6.
      eapply loader_valid_forward; eassumption. 

   destruct INV as [? [? ?]].
     specialize (mem_wd_alloc _ _ _ _ _ H0 H2). intros WD1.
     split; simpl. eapply store_args_wd. eassumption.  eassumption. 
       apply alloc_forward in H0. eapply vals_valid_fwd; eassumption.
     apply store_args_fwd in H1. 
     split. subst rs0. 
        apply regmap_valid_assign; simpl; trivial.
        eapply regmap_valid_forward; try eapply H1. 
        apply alloc_forward in H0.
        eapply regmap_valid_forward; try eapply H0.  
        apply regmap_valid_assign; simpl; trivial.
        apply regmap_valid_assign; simpl; trivial.
        red; intros. rewrite Pregmap.gi. simpl; trivial.
        apply H1. apply (Mem.valid_new_block _ _ _ _ _ H0).
      apply H1. apply (Mem.valid_new_block _ _ _ _ _ H0). } 

{ intros ? ? ? ? ? ? INV ATEXT.
  destruct c; inv ATEXT.
  destruct (observableEF_dec hf f); inv H0.
  unfold Inv in INV.
  destruct INV as [MEM [REGS [LF VALS]]]. 
  split; trivial.
  apply vals_valid_decode; assumption. }

{ intros ? ? ? ? ? INV AFTEREXT OVAL FWD WD'.
  destruct c; inv AFTEREXT. 
  unfold Inv in INV.
  destruct INV as [MEM [REGS [LF VALS]]]. 
  destruct ov; inv H0.
  { (*Case ov = Some v*)
    split; trivial.
    split. 
      apply regmap_valid_assign; simpl; trivial.
      unfold loc_external_result, loc_result.
      remember (sig_res (ef_sig f)) as ty. 
      destruct ty; simpl.
        destruct t; simpl; simpl in OVAL.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         unfold Val.hiword. destruct v; simpl; trivial.
         unfold Val.loword. destruct v; simpl; trivial.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         eapply Nuke_sem.val_valid_fwd. apply REGS. trivial.
     eapply loader_valid_forward; eassumption. }
  { (*Case ov = None*)
    split; trivial.
    split.
      apply regmap_valid_assign; simpl; trivial.
      unfold loc_external_result, loc_result.
      remember (sig_res (ef_sig f)) as ty. 
      destruct ty; simpl.
        destruct t; simpl; simpl in OVAL.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         apply regmap_valid_assign; simpl; trivial.
         eapply regmap_valid_forward; eassumption.
         eapply Nuke_sem.val_valid_fwd. apply REGS. trivial.
     eapply loader_valid_forward; eassumption. } }

{ intros ? ? ? INV HALTED.
  destruct c; inv HALTED. 
  unfold Inv in INV.
  destruct INV as [MEM [REGS LF]]. 
  split; trivial.
  destruct loader.
  destruct (Val.cmp_bool Ceq (rs PC) Vzero); inv H0.
  destruct retty. 
    destruct t; inv H1; simpl; trivial.
    unfold Val.longofwords.
    destruct (rs EDX); simpl; trivial. 
    destruct (rs EAX); simpl; trivial. 
  inv H1. apply REGS. }
Qed.