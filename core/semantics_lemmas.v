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
Require Import semantics.

Definition corestep_fun {G C M : Type} (sem : CoreSemantics G C M) :=
  forall (m m' m'' : M) ge c c' c'',
  corestep sem ge c m c' m' -> 
  corestep sem ge c m c'' m'' -> 
  c'=c'' /\ m'=m''.

(**  Multistepping *)

Section corestepN.
  Context {G C M E:Type} (Sem:CoreSemantics G C M) (ge:G).

  Fixpoint corestepN (n:nat) : C -> M -> C -> M -> Prop :=
    match n with
      | O => fun c m c' m' => (c,m) = (c',m')
      | S k => fun c1 m1 c3 m3 => exists c2, exists m2,
        corestep Sem ge c1 m1 c2 m2 /\
        corestepN k c2 m2 c3 m3
    end.

  Lemma corestepN_add : forall n m c1 m1 c3 m3,
    corestepN (n+m) c1 m1 c3 m3 <->
    exists c2, exists m2,
      corestepN n c1 m1 c2 m2 /\
      corestepN m c2 m2 c3 m3.
  Proof.
    induction n; simpl; intuition.
    firstorder. firstorder.
    inv H. auto.
    decompose [ex and] H. clear H.
    destruct (IHn m x x0 c3 m3).
    apply H in H2. 
    decompose [ex and] H2. clear H2.
    repeat econstructor; eauto.
    decompose [ex and] H. clear H.
    exists x1. exists x2; split; auto.
    destruct (IHn m x1 x2 c3 m3). 
    eauto.
  Qed.

  Definition corestep_plus c m c' m' :=
    exists n, corestepN (S n) c m c' m'.

  Definition corestep_star c m c' m' :=
    exists n, corestepN n c m c' m'.

  Lemma corestep_plus_star : forall c1 c2 m1 m2,
    corestep_plus c1 m1 c2 m2 -> corestep_star c1 m1 c2 m2.
  Proof. intros. destruct H as [n1 H1]. eexists. apply H1. Qed.

  Lemma corestep_plus_trans : forall c1 c2 c3 m1 m2 m3,
    corestep_plus c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add (S n1) (S n2) c1 m1 c3 m3) as [_ H].
    eexists. apply H. exists c2. exists m2. split; assumption.
  Qed.

  Lemma corestep_star_plus_trans : forall c1 c2 c3 m1 m2 m3,
    corestep_star c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add n1 (S n2) c1 m1 c3 m3) as [_ H]. 
    rewrite <- plus_n_Sm in H.
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_plus_star_trans: forall c1 c2 c3 m1 m2 m3,
    corestep_plus c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add (S n1) n2 c1 m1 c3 m3) as [_ H]. 
    rewrite plus_Sn_m in H.
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_star_trans: forall c1 c2 c3 m1 m2 m3, 
    corestep_star c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> 
    corestep_star c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add n1 n2 c1 m1 c3 m3) as [_ H]. 
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_plus_one: forall c m c' m',
    corestep  Sem ge c m c' m' -> corestep_plus c m c' m'.
  Proof. intros. unfold corestep_plus, corestepN. simpl.
    exists O. exists c'. exists m'. eauto. 
  Qed.

  Lemma corestep_plus_two: forall c m c' m' c'' m'',
    corestep  Sem ge c m c' m' -> corestep  Sem ge c' m' c'' m'' -> 
    corestep_plus c m c'' m''.
  Proof. intros. 
    exists (S O). exists c'. exists m'. split; trivial. 
    exists c''. exists m''. split; trivial. reflexivity.
  Qed.

  Lemma corestep_star_zero: forall c m, corestep_star  c m c m.
  Proof. intros. exists O. reflexivity. Qed.

  Lemma corestep_star_one: forall c m c' m',
    corestep  Sem ge c m c' m' -> corestep_star c m c' m'.
  Proof. intros. 
    exists (S O). exists c'. exists m'. split; trivial. reflexivity. 
  Qed.

  Lemma corestep_plus_split: forall c m c' m',
    corestep_plus c m c' m' ->
    exists c'', exists m'', corestep  Sem ge c m c'' m'' /\ 
      corestep_star c'' m'' c' m'.
  Proof. intros.
    destruct H as [n [c2 [m2 [Hstep Hstar]]]]. simpl in*. 
    exists c2. exists m2. split. assumption. exists n. assumption.  
  Qed.

End corestepN.

Lemma memsem_preservesN {G C} (s: @MemSem G C) P (HP: memstep_preserve P):
      forall g n c m c' m', corestepN s g n c m c' m'-> P m m'.
Proof.
 intros g; induction n; intros.
 inv H. apply (preserve_refl HP).
 inv H. destruct H0 as [mm [? ?]].
 eapply (preserve_trans _ HP).
 eapply (memsem_preserves _ _ HP); eassumption.
 apply IHn in H0; trivial.
Qed. 

Lemma memsem_preserves_plus {G C} (s: @MemSem G C) P (HP:memstep_preserve P):
      forall g c m c' m', corestep_plus s g c m c' m'-> P m m'.
Proof.
 intros. destruct H. apply (memsem_preservesN _ _ HP) in H; trivial.
Qed.

Lemma coalg_preserves_star {G C} (s: @MemSem G C) P (HP:memstep_preserve P):
      forall g c m c' m', corestep_star s g c m c' m'-> P m m'.
Proof.
 intros. destruct H. apply (memsem_preservesN _ _ HP) in H; trivial.
Qed.


Section CoopCoreSemLemmas.
Context {G C: Type}.
Variable coopsem: CoopCoreSem G C.

Lemma corestepN_fwd: forall ge c m c' m' n,
  corestepN coopsem ge n c m c' m' -> 
  mem_forward m m'.
Proof.
intros until n; revert c m.
induction n; simpl; auto.
inversion 1; apply mem_forward_refl; auto.
intros c m [c2 [m2 [? ?]]].
apply mem_forward_trans with (m2 := m2).
apply corestep_fwd in H; auto.
eapply IHn; eauto.
Qed.

Lemma corestep_star_fwd: forall g c m c' m'
  (CS:corestep_star coopsem g c m c' m'), 
  mem_forward m m'.
Proof. 
  intros. destruct CS. 
  eapply corestepN_fwd. 
  apply H.
Qed.

Lemma corestep_plus_fwd: forall g c m c' m'
  (CS:corestep_plus coopsem g c m c' m'), 
  mem_forward m m'.
Proof.
   intros. destruct CS.
   eapply corestepN_fwd.
   apply H.
Qed.

Lemma corestepN_rdonly: forall ge c m c' m' n,
  corestepN coopsem ge n c m c' m' -> forall b
  (VB: Mem.valid_block m b), readonly m b m'.
Proof.
intros until n; revert c m.
induction n; simpl; auto.
inversion 1; intros. apply readonly_refl.
intros c m [c2 [m2 [? ?]]].
intros. apply readonly_trans with (m2 := m2).
eapply corestep_rdonly; eauto.
eapply IHn; eauto. eapply corestep_fwd; eauto.
Qed.

Lemma corestep_plus_rdonly ge c m c' m'
  (CS: corestep_plus coopsem ge c m c' m') b
  (VB: Mem.valid_block m b): readonly m b m'.
Proof.
  destruct CS. eapply corestepN_rdonly; eauto. 
Qed.

Lemma corestep_star_rdonly ge c m c' m'
  (CS: corestep_star coopsem ge c m c' m') b
  (VB: Mem.valid_block m b): readonly m b m'.
Proof.
  destruct CS. eapply corestepN_rdonly; eauto. 
Qed.

End CoopCoreSemLemmas.
