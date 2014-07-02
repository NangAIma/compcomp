Require Import Coqlib.
Require Export Axioms.
Require Import Errors.
Require Import Maps.
Require Import Integers.
Require Import Floats.
Require Import AST.
Require Import Values.
Require Import Events.
Require Import Memory.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Ctypes.
Require Import Cop.
Require Import Clight.
Require Import Cminor.
Require Import Csharpminor.
Require Import Cshmgen.

Require Import Clight_coop.
Require Import Clight_eff.
Require Import Csharpminor_coop.
Require Import Csharpminor_eff.

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

Lemma assign_loc_freshloc: forall ty m b ofs v m' (AL:assign_loc ty m b ofs v m'),
  freshloc m m' = fun b => false.
Proof. intros.
  inv AL. apply (storev_freshloc _ _ _ _ _ H0).
  apply (storebytes_freshloc _ _ _ _ _ H4).
Qed. 

(** * Properties of operations over types *)

Remark transl_params_types:
  forall params,
  map typ_of_type (map snd params) = typlist_of_typelist (type_of_params params).
Proof.
  induction params; simpl. auto. destruct a as [id ty]; simpl. f_equal; auto.
Qed.

Lemma transl_fundef_sig1:
  forall f tf args res,
  transl_fundef f = OK tf ->
  classify_fun (type_of_fundef f) = fun_case_f args res ->
  funsig tf = signature_of_type args res.
Proof.
  intros. destruct f; simpl in *. 
  monadInv H. monadInv EQ. simpl. inversion H0.    
  unfold signature_of_function, signature_of_type.
  f_equal. apply transl_params_types.
  destruct (list_typ_eq (sig_args (ef_sig e)) (typlist_of_typelist t)); simpl in H.
  destruct (opt_typ_eq (sig_res (ef_sig e)) (opttyp_of_type t0)); simpl in H.
  inv H. simpl. destruct (ef_sig e); simpl in *. inv H0.
  unfold signature_of_type. auto.
  congruence.
  congruence.
Qed.

Lemma transl_fundef_sig2:
  forall f tf args res,
  transl_fundef f = OK tf ->
  type_of_fundef f = Tfunction args res ->
  funsig tf = signature_of_type args res.
Proof.
  intros. eapply transl_fundef_sig1; eauto.
  rewrite H0; reflexivity.
Qed.

(** * Properties of the translation functions *)

(** Transformation of expressions and statements. *)

Lemma transl_expr_lvalue:
  forall ge e le m a loc ofs ta,
  Clight.eval_lvalue ge e le m a loc ofs ->
  transl_expr a = OK ta ->
  (exists tb, transl_lvalue a = OK tb /\ make_load tb (typeof a) = OK ta).
Proof.
  intros until ta; intros EVAL TR. inv EVAL; simpl in TR.
  (* var local *)
  exists (Eaddrof id); auto.
  (* var global *)
  exists (Eaddrof id); auto.
  (* deref *)
  monadInv TR. exists x; auto.
  (* field struct *)
  rewrite H0 in TR. monadInv TR.
  econstructor; split. simpl. rewrite H0.
  rewrite EQ; rewrite EQ1; simpl; eauto. auto.
  (* field union *)
  rewrite H0 in TR. monadInv TR.
  econstructor; split. simpl. rewrite H0. rewrite EQ; simpl; eauto. auto.
Qed.

(** Properties of labeled statements *)

Lemma transl_lbl_stmt_1:
  forall tyret nbrk ncnt n sl tsl,
  transl_lbl_stmt tyret nbrk ncnt sl = OK tsl ->
  transl_lbl_stmt tyret nbrk ncnt (Clight.select_switch n sl) = OK (select_switch n tsl).
Proof.
  induction sl; intros.
  monadInv H. simpl. rewrite EQ. auto.
  generalize H; intro TR. monadInv TR. simpl. 
  destruct (Int.eq i n). auto. auto. 
Qed.

Lemma transl_lbl_stmt_2:
  forall tyret nbrk ncnt sl tsl,
  transl_lbl_stmt tyret nbrk ncnt sl = OK tsl ->
  transl_statement tyret nbrk ncnt (seq_of_labeled_statement sl) = OK (seq_of_lbl_stmt tsl).
Proof.
  induction sl; intros.
  monadInv H. simpl. auto.
  monadInv H. simpl. rewrite EQ; simpl. rewrite (IHsl _ EQ1). simpl. auto.
Qed.

(** * Correctness of Csharpminor construction functions *)

Section CONSTRUCTORS.
(*NEW*) Variable hf : I64Helpers.helper_functions.

Variable ge: genv.

Lemma make_intconst_correct:
  forall n e le m,
  eval_expr ge e le m (make_intconst n) (Vint n).
Proof.
  intros. unfold make_intconst. econstructor. reflexivity. 
Qed.

Lemma make_floatconst_correct:
  forall n e le m,
  eval_expr ge e le m (make_floatconst n) (Vfloat n).
Proof.
  intros. unfold make_floatconst. econstructor. reflexivity. 
Qed.

Lemma make_longconst_correct:
  forall n e le m,
  eval_expr ge e le m (make_longconst n) (Vlong n).
Proof.
  intros. unfold make_floatconst. econstructor. reflexivity. 
Qed.

Lemma make_floatofint_correct:
  forall a n sg sz e le m,
  eval_expr ge e le m a (Vint n) ->
  eval_expr ge e le m (make_floatofint a sg sz) (Vfloat(cast_int_float sg sz n)).
Proof.
  intros. unfold make_floatofint, cast_int_float.
  destruct sz.
  destruct sg. 
  rewrite Float.singleofint_floatofint. econstructor. econstructor; eauto. simpl; reflexivity. auto.
  rewrite Float.singleofintu_floatofintu. econstructor. econstructor; eauto. simpl; reflexivity. auto.
  destruct sg; econstructor; eauto. 
Qed.

Lemma make_intoffloat_correct:
  forall e le m a sg f i,
  eval_expr ge e le m a (Vfloat f) ->
  cast_float_int sg f = Some i ->
  eval_expr ge e le m (make_intoffloat a sg) (Vint i).
Proof.
  unfold cast_float_int, make_intoffloat; intros.
  destruct sg; econstructor; eauto; simpl; rewrite H0; auto.
Qed.

Lemma make_longofint_correct:
  forall a n sg e le m,
  eval_expr ge e le m a (Vint n) ->
  eval_expr ge e le m (make_longofint a sg) (Vlong(cast_int_long sg n)).
Proof.
  intros. unfold make_longofint, cast_int_long. 
  destruct sg; econstructor; eauto. 
Qed.

Lemma make_floatoflong_correct:
  forall a n sg sz e le m,
  eval_expr ge e le m a (Vlong n) ->
  eval_expr ge e le m (make_floatoflong a sg sz) (Vfloat(cast_long_float sg sz n)).
Proof.
  intros. unfold make_floatoflong, cast_int_long. 
  destruct sg; destruct sz; econstructor; eauto. 
Qed.

Lemma make_longoffloat_correct:
  forall e le m a sg f i,
  eval_expr ge e le m a (Vfloat f) ->
  cast_float_long sg f = Some i ->
  eval_expr ge e le m (make_longoffloat a sg) (Vlong i).
Proof.
  unfold cast_float_long, make_longoffloat; intros.
  destruct sg; econstructor; eauto; simpl; rewrite H0; auto.
Qed.

Hint Resolve make_intconst_correct make_floatconst_correct make_longconst_correct
             make_floatofint_correct make_intoffloat_correct
             make_longofint_correct
             make_floatoflong_correct make_longoffloat_correct
             eval_Eunop eval_Ebinop: cshm.
Hint Extern 2 (@eq trace _ _) => traceEq: cshm.

Lemma make_cmp_ne_zero_correct:
  forall e le m a n,
  eval_expr ge e le m a (Vint n) ->
  eval_expr ge e le m (make_cmp_ne_zero a) (Vint (if Int.eq n Int.zero then Int.zero else Int.one)).
Proof.
  intros. 
  assert (DEFAULT: eval_expr ge e le m (Ebinop (Ocmp Cne) a (make_intconst Int.zero))
                                       (Vint (if Int.eq n Int.zero then Int.zero else Int.one))).
    econstructor; eauto with cshm. simpl. unfold Val.cmp, Val.cmp_bool. 
    unfold Int.cmp. destruct (Int.eq n Int.zero); auto. 
  assert (CMP: forall ob,
               Val.of_optbool ob = Vint n ->
               n = (if Int.eq n Int.zero then Int.zero else Int.one)).
    intros. destruct ob; simpl in H0; inv H0. destruct b; inv H2. 
    rewrite Int.eq_false. auto. apply Int.one_not_zero.
    rewrite Int.eq_true. auto.
  destruct a; simpl; auto. destruct b; auto. 
  inv H. econstructor; eauto. rewrite H6. decEq. decEq. 
  simpl in H6. inv H6. unfold Val.cmp in H0. eauto.
  inv H. econstructor; eauto. rewrite H6. decEq. decEq. 
  simpl in H6. inv H6. unfold Val.cmp in H0. eauto.
  inv H. econstructor; eauto. rewrite H6. decEq. decEq. 
  simpl in H6. inv H6. unfold Val.cmp in H0. eauto.
  inv H. econstructor; eauto. rewrite H6. decEq. decEq. 
  simpl in H6. unfold Val.cmpl in H6.
  destruct (Val.cmpl_bool c v1 v2) as [[]|]; inv H6; reflexivity. 
  inv H. econstructor; eauto. rewrite H6. decEq. decEq. 
  simpl in H6. unfold Val.cmplu in H6.
  destruct (Val.cmplu_bool c v1 v2) as [[]|]; inv H6; reflexivity. 
Qed.

Lemma make_cast_int_correct:
  forall e le m a n sz si,
  eval_expr ge e le m a (Vint n) ->
  eval_expr ge e le m (make_cast_int a sz si) (Vint (cast_int_int sz si n)).
Proof.
  intros. unfold make_cast_int, cast_int_int. 
  destruct sz.
  destruct si; eauto with cshm.
  destruct si; eauto with cshm.
  auto.
  apply make_cmp_ne_zero_correct; auto.
Qed.

Lemma make_cast_float_correct:
  forall e le m a n sz,
  eval_expr ge e le m a (Vfloat n) ->
  eval_expr ge e le m (make_cast_float a sz) (Vfloat (cast_float_float sz n)).
Proof.
  intros. unfold make_cast_float, cast_float_float. 
  destruct sz. eauto with cshm. auto.
Qed.

Hint Resolve make_cast_int_correct make_cast_float_correct: cshm.

Lemma make_cast_correct:
  forall e le m a b v ty1 ty2 v',
  make_cast ty1 ty2 a = OK b ->
  eval_expr ge e le m a v ->
  sem_cast v ty1 ty2 = Some v' ->
  eval_expr ge e le m b v'.
Proof.
  intros. unfold make_cast, sem_cast in *;
  destruct (classify_cast ty1 ty2); inv H; destruct v; inv H1; eauto with cshm.
  (* float -> int *)
  destruct (cast_float_int si2 f) as [i|] eqn:E; inv H2. eauto with cshm.
  (* float -> long *)
  destruct (cast_float_long si2 f) as [i|] eqn:E; inv H2. eauto with cshm.
  (* float -> bool *)
  econstructor; eauto with cshm.
  simpl. unfold Val.cmpf, Val.cmpf_bool. rewrite Float.cmp_ne_eq.
  destruct (Float.cmp Ceq f Float.zero); auto.
  (* long -> bool *)
  econstructor; eauto with cshm.
  simpl. unfold Val.cmpl, Val.cmpl_bool, Int64.cmp.
  destruct (Int64.eq i Int64.zero); auto.
  (* int -> bool *)
  econstructor; eauto with cshm.
  simpl. unfold Val.cmpu, Val.cmpu_bool, Int.cmpu.
  destruct (Int.eq i Int.zero); auto.
  (* struct *)
  destruct (ident_eq id1 id2 && fieldlist_eq fld1 fld2); inv H2; auto.
  (* union *)
  destruct (ident_eq id1 id2 && fieldlist_eq fld1 fld2); inv H2; auto.
Qed.
(*Replaced by make_boolean_inject below
Lemma make_boolean_correct:
 forall e le m a v ty b,
  eval_expr ge e le m a v ->
  bool_val v ty = Some b ->
  exists vb,
    eval_expr ge e le m (make_boolean a ty) vb
    /\ Val.bool_of_val vb b.
Proof.
  intros. unfold make_boolean. unfold bool_val in H0. 
  destruct (classify_bool ty); destruct v; inv H0.
(* int *)
  econstructor; split. apply make_cmp_ne_zero_correct with (n := i); auto. 
  destruct (Int.eq i Int.zero); simpl; constructor. 
(* float *)
  econstructor; split. econstructor; eauto with cshm. simpl. eauto. 
  unfold Val.cmpf, Val.cmpf_bool. simpl. rewrite <- Float.cmp_ne_eq. 
  destruct (Float.cmp Cne f Float.zero); constructor. 
(* pointer *)
  econstructor; split. econstructor; eauto with cshm. simpl. eauto. 
  unfold Val.cmpu, Val.cmpu_bool. simpl.
  destruct (Int.eq i Int.zero); simpl; constructor.
  exists Vtrue; split. econstructor; eauto with cshm. constructor.
(* long *)
  econstructor; split. econstructor; eauto with cshm. simpl. unfold Val.cmpl. simpl. eauto. 
  destruct (Int64.eq i Int64.zero); simpl; constructor. 
Qed.
*)

Lemma make_neg_correct:
  forall a tya c va v e le m,
  sem_neg va tya = Some v ->
  make_neg a tya = OK c ->  
  eval_expr ge e le m a va ->
  eval_expr ge e le m c v.
Proof.
  unfold sem_neg, make_neg; intros until m; intros SEM MAKE EV1;
  destruct (classify_neg tya); inv MAKE; destruct va; inv SEM; eauto with cshm.
Qed.

Lemma make_notbool_correct:
  forall a tya c va v e le m,
  sem_notbool va tya = Some v ->
  make_notbool a tya = OK c ->  
  eval_expr ge e le m a va ->
  eval_expr ge e le m c v.
Proof.
  unfold sem_notbool, make_notbool; intros until m; intros SEM MAKE EV1;
  destruct (classify_bool tya); inv MAKE; destruct va; inv SEM; eauto with cshm.
Qed.

Lemma make_notint_correct:
  forall a tya c va v e le m,
  sem_notint va tya = Some v ->
  make_notint a tya = OK c ->  
  eval_expr ge e le m a va ->
  eval_expr ge e le m c v.
Proof.
  unfold sem_notint, make_notint; intros until m; intros SEM MAKE EV1;
  destruct (classify_notint tya); inv MAKE; destruct va; inv SEM; eauto with cshm.
Qed.

Definition binary_constructor_correct
    (make: expr -> type -> expr -> type -> res expr)
    (sem: val -> type -> val -> type -> option val): Prop :=
  forall a tya b tyb c va vb v e le m,
  sem va tya vb tyb = Some v ->
  make a tya b tyb = OK c ->  
  eval_expr ge e le m a va ->
  eval_expr ge e le m b vb ->
  eval_expr ge e le m c v.

Section MAKE_BIN.

Variable sem_int: signedness -> int -> int -> option val.
Variable sem_long: signedness -> int64 -> int64 -> option val.
Variable sem_float: float -> float -> option val.
Variables iop iopu fop lop lopu: binary_operation.

Hypothesis iop_ok:
  forall x y m, eval_binop iop (Vint x) (Vint y) m = sem_int Signed x y.
Hypothesis iopu_ok:
  forall x y m, eval_binop iopu (Vint x) (Vint y) m = sem_int Unsigned x y.
Hypothesis lop_ok:
  forall x y m, eval_binop lop (Vlong x) (Vlong y) m = sem_long Signed x y.
Hypothesis lopu_ok:
  forall x y m, eval_binop lopu (Vlong x) (Vlong y) m = sem_long Unsigned x y.
Hypothesis fop_ok:
  forall x y m, eval_binop fop (Vfloat x) (Vfloat y) m = sem_float x y.

Lemma make_binarith_correct:
  binary_constructor_correct
    (make_binarith iop iopu fop lop lopu)
    (sem_binarith sem_int sem_long sem_float).
Proof.
  red; unfold make_binarith, sem_binarith;
  intros until m; intros SEM MAKE EV1 EV2.
  set (cls := classify_binarith tya tyb) in *.
  set (ty := binarith_type cls) in *.
  monadInv MAKE.
  destruct (sem_cast va tya ty) as [va'|] eqn:Ca; try discriminate.
  destruct (sem_cast vb tyb ty) as [vb'|] eqn:Cb; try discriminate.
  exploit make_cast_correct. eexact EQ. eauto. eauto. intros EV1'.
  exploit make_cast_correct. eexact EQ1. eauto. eauto. intros EV2'.
  destruct cls; inv EQ2; destruct va'; try discriminate; destruct vb'; try discriminate.
- destruct s; inv H0; econstructor; eauto with cshm. 
  rewrite iop_ok; auto. rewrite iopu_ok; auto.
- destruct s; inv H0; econstructor; eauto with cshm. 
  rewrite lop_ok; auto. rewrite lopu_ok; auto.
- erewrite <- fop_ok in SEM; eauto with cshm.
Qed.

Lemma make_binarith_int_correct:
  binary_constructor_correct
    (make_binarith_int iop iopu lop lopu)
    (sem_binarith sem_int sem_long (fun x y => None)).
Proof.
  red; unfold make_binarith_int, sem_binarith;
  intros until m; intros SEM MAKE EV1 EV2.
  set (cls := classify_binarith tya tyb) in *.
  set (ty := binarith_type cls) in *.
  monadInv MAKE.
  destruct (sem_cast va tya ty) as [va'|] eqn:Ca; try discriminate.
  destruct (sem_cast vb tyb ty) as [vb'|] eqn:Cb; try discriminate.
  exploit make_cast_correct. eexact EQ. eauto. eauto. intros EV1'.
  exploit make_cast_correct. eexact EQ1. eauto. eauto. intros EV2'.
  destruct cls; inv EQ2; destruct va'; try discriminate; destruct vb'; try discriminate.
- destruct s; inv H0; econstructor; eauto with cshm. 
  rewrite iop_ok; auto. rewrite iopu_ok; auto.
- destruct s; inv H0; econstructor; eauto with cshm. 
  rewrite lop_ok; auto. rewrite lopu_ok; auto.
Qed.

End MAKE_BIN.

Hint Extern 2 (@eq (option val) _ _) => (simpl; reflexivity) : cshm.

Lemma make_add_correct: binary_constructor_correct make_add sem_add.
Proof.
  red; unfold make_add, sem_add;
  intros until m; intros SEM MAKE EV1 EV2;
  destruct (classify_add tya tyb); inv MAKE.
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- eapply make_binarith_correct; eauto; intros; auto.
Qed.

Lemma make_sub_correct: binary_constructor_correct make_sub sem_sub.
Proof.
  red; unfold make_sub, sem_sub;
  intros until m; intros SEM MAKE EV1 EV2;
  destruct (classify_sub tya tyb); inv MAKE.
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- destruct va; try discriminate; destruct vb; inv SEM.
  destruct (eq_block b0 b1); try discriminate. destruct (Int.eq (Int.repr (sizeof ty)) Int.zero) eqn:E; inv H0.
  econstructor; eauto with cshm. rewrite dec_eq_true. simpl. rewrite E; auto. 
- destruct va; try discriminate; destruct vb; inv SEM; eauto with cshm.
- eapply make_binarith_correct; eauto; intros; auto.
Qed.

Lemma make_mul_correct: binary_constructor_correct make_mul sem_mul.
Proof.
  apply make_binarith_correct; intros; auto.
Qed.

Lemma make_div_correct: binary_constructor_correct make_div sem_div.
Proof.
  apply make_binarith_correct; intros; auto.
Qed.

Lemma make_mod_correct: binary_constructor_correct make_mod sem_mod.
Proof.
  apply make_binarith_int_correct; intros; auto.
Qed.

Lemma make_and_correct: binary_constructor_correct make_and sem_and.
Proof.
  apply make_binarith_int_correct; intros; auto.
Qed.

Lemma make_or_correct: binary_constructor_correct make_or sem_or.
Proof.
  apply make_binarith_int_correct; intros; auto.
Qed.

Lemma make_xor_correct: binary_constructor_correct make_xor sem_xor.
Proof.
  apply make_binarith_int_correct; intros; auto.
Qed.

Ltac comput val :=
  let x := fresh in set val as x in *; vm_compute in x; subst x.

Remark small_shift_amount_1:
  forall i,
  Int64.ltu i Int64.iwordsize = true ->
  Int.ltu (Int64.loword i) Int64.iwordsize' = true
  /\ Int64.unsigned i = Int.unsigned (Int64.loword i).
Proof.
  intros. apply Int64.ltu_inv in H. comput (Int64.unsigned Int64.iwordsize). 
  assert (Int64.unsigned i = Int.unsigned (Int64.loword i)).
  {
    unfold Int64.loword. rewrite Int.unsigned_repr; auto. 
    comput Int.max_unsigned; omega.
  }
  split; auto. unfold Int.ltu. apply zlt_true. rewrite <- H0. tauto.
Qed.

Remark small_shift_amount_2:
  forall i,
  Int64.ltu i (Int64.repr 32) = true ->
  Int.ltu (Int64.loword i) Int.iwordsize = true.
Proof.
  intros. apply Int64.ltu_inv in H. comput (Int64.unsigned (Int64.repr 32)).
  assert (Int64.unsigned i = Int.unsigned (Int64.loword i)).
  {
    unfold Int64.loword. rewrite Int.unsigned_repr; auto. 
    comput Int.max_unsigned; omega.
  }
  unfold Int.ltu. apply zlt_true. rewrite <- H0. tauto.
Qed.

Lemma small_shift_amount_3:
  forall i,
  Int.ltu i Int64.iwordsize' = true ->
  Int64.unsigned (Int64.repr (Int.unsigned i)) = Int.unsigned i.
Proof.
  intros. apply Int.ltu_inv in H. comput (Int.unsigned Int64.iwordsize'). 
  apply Int64.unsigned_repr. comput Int64.max_unsigned; omega.
Qed.

Lemma make_shl_correct: binary_constructor_correct make_shl sem_shl.
Proof.
  red; unfold make_shl, sem_shl, sem_shift;
  intros until m; intros SEM MAKE EV1 EV2;
  destruct (classify_shift tya tyb); inv MAKE;
  destruct va; try discriminate; destruct vb; try discriminate.
- destruct (Int.ltu i0 Int.iwordsize) eqn:E; inv SEM.
  econstructor; eauto. simpl; rewrite E; auto.
- destruct (Int64.ltu i0 Int64.iwordsize) eqn:E; inv SEM.
  exploit small_shift_amount_1; eauto. intros [A B].
  econstructor; eauto with cshm. simpl. rewrite A. 
  f_equal; f_equal. unfold Int64.shl', Int64.shl. rewrite B; auto.
- destruct (Int64.ltu i0 (Int64.repr 32)) eqn:E; inv SEM.
  econstructor; eauto with cshm. simpl. rewrite small_shift_amount_2; auto. 
- destruct (Int.ltu i0 Int64.iwordsize') eqn:E; inv SEM. 
  econstructor; eauto with cshm. simpl. rewrite E. 
  unfold Int64.shl', Int64.shl. rewrite small_shift_amount_3; auto.
Qed.

Lemma make_shr_correct: binary_constructor_correct make_shr sem_shr.
Proof.
  red; unfold make_shr, sem_shr, sem_shift;
  intros until m; intros SEM MAKE EV1 EV2;
  destruct (classify_shift tya tyb); inv MAKE;
  destruct va; try discriminate; destruct vb; try discriminate.
- destruct (Int.ltu i0 Int.iwordsize) eqn:E; inv SEM.
  destruct s; inv H0; econstructor; eauto; simpl; rewrite E; auto.
- destruct (Int64.ltu i0 Int64.iwordsize) eqn:E; inv SEM.
  exploit small_shift_amount_1; eauto. intros [A B].
  destruct s; inv H0; econstructor; eauto with cshm; simpl; rewrite A;
  f_equal; f_equal.
  unfold Int64.shr', Int64.shr; rewrite B; auto.
  unfold Int64.shru', Int64.shru; rewrite B; auto.
- destruct (Int64.ltu i0 (Int64.repr 32)) eqn:E; inv SEM.
  destruct s; inv H0; econstructor; eauto with cshm; simpl; rewrite small_shift_amount_2; auto. 
- destruct (Int.ltu i0 Int64.iwordsize') eqn:E; inv SEM.
  destruct s; inv H0; econstructor; eauto with cshm; simpl; rewrite E. 
  unfold Int64.shr', Int64.shr; rewrite small_shift_amount_3; auto.
  unfold Int64.shru', Int64.shru; rewrite small_shift_amount_3; auto.
Qed.

Lemma make_cmp_correct:
  forall cmp a tya b tyb c va vb v e le m,
  sem_cmp cmp va tya vb tyb m = Some v ->
  make_cmp cmp a tya b tyb = OK c ->  
  eval_expr ge e le m a va ->
  eval_expr ge e le m b vb ->
  eval_expr ge e le m c v.
Proof.
  unfold sem_cmp, make_cmp; intros until m; intros SEM MAKE EV1 EV2;
  destruct (classify_cmp tya tyb).
- inv MAKE. destruct (Val.cmpu_bool (Mem.valid_pointer m) cmp va vb) as [bv|] eqn:E;
  simpl in SEM; inv SEM.
  econstructor; eauto. simpl. unfold Val.cmpu. rewrite E. auto.
- inv MAKE. destruct vb; try discriminate. 
  set (vb := Vint (Int.repr (Int64.unsigned i))) in *.
  destruct (Val.cmpu_bool (Mem.valid_pointer m) cmp va vb) as [bv|] eqn:E;
  simpl in SEM; inv SEM.
  econstructor; eauto with cshm. simpl. change (Vint (Int64.loword i)) with vb. 
  unfold Val.cmpu. rewrite E. auto.
- inv MAKE. destruct va; try discriminate. 
  set (va := Vint (Int.repr (Int64.unsigned i))) in *.
  destruct (Val.cmpu_bool (Mem.valid_pointer m) cmp va vb) as [bv|] eqn:E;
  simpl in SEM; inv SEM.
  econstructor; eauto with cshm. simpl. change (Vint (Int64.loword i)) with va. 
  unfold Val.cmpu. rewrite E. auto.
- eapply make_binarith_correct; eauto; intros; auto.
Qed.

Lemma transl_unop_correct:
  forall op a tya c va v e le m, 
  transl_unop op a tya = OK c ->
  sem_unary_operation op va tya = Some v ->
  eval_expr ge e le m a va ->
  eval_expr ge e le m c v.
Proof.
  intros. destruct op; simpl in *.
  eapply make_notbool_correct; eauto. 
  eapply make_notint_correct; eauto. 
  eapply make_neg_correct; eauto.
Qed.

Lemma transl_binop_correct:
  forall op a tya b tyb c va vb v e le m,
  transl_binop op a tya b tyb = OK c ->  
  sem_binary_operation op va tya vb tyb m = Some v ->
  eval_expr ge e le m a va ->
  eval_expr ge e le m b vb ->
  eval_expr ge e le m c v.
Proof.
  intros. destruct op; simpl in *.
  eapply make_add_correct; eauto.
  eapply make_sub_correct; eauto.
  eapply make_mul_correct; eauto.
  eapply make_div_correct; eauto.
  eapply make_mod_correct; eauto.
  eapply make_and_correct; eauto.
  eapply make_or_correct; eauto.
  eapply make_xor_correct; eauto.
  eapply make_shl_correct; eauto.
  eapply make_shr_correct; eauto.
  eapply make_cmp_correct; eauto.
  eapply make_cmp_correct; eauto.
  eapply make_cmp_correct; eauto.
  eapply make_cmp_correct; eauto.
  eapply make_cmp_correct; eauto.
  eapply make_cmp_correct; eauto.
Qed. 

Lemma make_load_correct:
  forall addr ty code b ofs v e le m,
  make_load addr ty = OK code ->
  eval_expr ge e le m addr (Vptr b ofs) ->
  deref_loc ty m b ofs v ->
  eval_expr ge e le m code v.
Proof.
  unfold make_load; intros until m; intros MKLOAD EVEXP DEREF.
  inv DEREF. 
  (* scalar *)
  rewrite H in MKLOAD. inv MKLOAD. apply eval_Eload with (Vptr b ofs); auto.
  (* by reference *)
  rewrite H in MKLOAD. inv MKLOAD. auto.
  (* by copy *)
  rewrite H in MKLOAD. inv MKLOAD. auto.
Qed.
(*
Lemma make_memcpy_correct:
  forall f dst src ty k e le m b ofs v m',
  eval_expr ge e le m dst (Vptr b ofs) ->
  eval_expr ge e le m src v ->
  assign_loc ty m b ofs v m' ->
  access_mode ty = By_copy ->
  step ge (State f (make_memcpy dst src ty) k e le m) E0 (State f Sskip k e le m').
Proof.
  intros. inv H1; try congruence. 
  unfold make_memcpy. change le with (set_optvar None Vundef le) at 2. 
  econstructor.
  econstructor. eauto. econstructor. eauto. constructor. 
  econstructor; eauto. 
  apply alignof_blockcopy_1248.
  apply sizeof_pos. 
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.
Qed.*)

(*Will be needed for builtin:*)
Lemma make_memcpy_correct:
  forall f dst src ty k e le m b ofs v m',
  eval_expr ge e le m dst (Vptr b ofs) ->
  eval_expr ge e le m src v ->
  assign_loc ty m b ofs v m' ->
  access_mode ty = By_copy ->
  CSharpMin_corestep hf ge (CSharpMin_State f (make_memcpy dst src ty) k e le) m
          (CSharpMin_State f Sskip k e le) m'.
Proof.
  intros. inv H1; try congruence. 
  unfold make_memcpy. change le with (set_optvar None Vundef le) at 2. 
  econstructor.
  econstructor. eauto. econstructor. eauto. constructor. 
  econstructor; eauto. 
  apply alignof_blockcopy_1248.
  apply sizeof_pos. 
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.
  simpl. auto.
Qed.

Lemma make_memcpy_correct_BuiltinEffect:
     forall f dst src ty k e le m b ofs v m',
       eval_expr ge e le m dst (Vptr b ofs) ->
       eval_expr ge e le m src v ->
       assign_loc ty m b ofs v m' ->
       access_mode ty = By_copy ->
  exists b' ofs', v = Vptr b' ofs' /\
  effstep (csharpmin_eff_sem hf) ge
          (BuiltinEffect ge (EF_memcpy (sizeof ty) (alignof_blockcopy ty))
                            (Vptr b ofs :: Vptr b' ofs' :: nil) m)
          (CSharpMin_State f (make_memcpy dst src ty) k e le) m
          (CSharpMin_State f Sskip k e le) m'.
Proof.
  intros. inv H1; try congruence. 
  unfold make_memcpy. change le with (set_optvar None Vundef le) at 2. 
  exists b', ofs'. split; trivial.
  econstructor.
  econstructor. eauto. econstructor. eauto. constructor. 
  econstructor; eauto. 
  apply alignof_blockcopy_1248.
  apply sizeof_pos. 
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.
  simpl. auto. 
Qed.
(*
Lemma make_memcpy_correct_BuiltinEffect:
     forall f dst src ty k e le m b ofs v m',
       eval_expr ge e le m dst (Vptr b ofs) ->
       eval_expr ge e le m src v ->
       assign_loc ty m b ofs v m' ->
       access_mode ty = By_copy ->
  exists b' ofs', v = Vptr b' ofs' /\
  effstep (csharpmin_eff_sem hf) ge
          (BuiltinEffect ge (ef_sig (EF_memcpy (sizeof ty) (alignof_blockcopy ty)))
                            (Vptr b ofs :: Vptr b' ofs' :: nil) m)
          (CSharpMin_State f (make_memcpy dst src ty) k e le) m
          (CSharpMin_State f Sskip k e le) m'.
Proof.
  intros. inv H1; try congruence. 
  unfold make_memcpy. change le with (set_optvar None Vundef le) at 2. 
  exists b', ofs'. split; trivial.
  econstructor.
  econstructor. eauto. econstructor. eauto. constructor. 
  econstructor; eauto. 
  apply alignof_blockcopy_1248.
  apply sizeof_pos. 
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.  
Qed.
*)
(*WILL be needed for builtin
Lemma make_memcpy_correct_assignlocEffect:
     forall f dst src ty k e le m b ofs v m',
       eval_expr ge e le m dst (Vptr b ofs) ->
       eval_expr ge e le m src v ->
       assign_loc ty m b ofs v m' ->
       access_mode ty = By_copy ->
  exists b' ofs', v = Vptr b' ofs' /\
  effstep (csharpmin_eff_sem hf) ge
          (assign_loc_Effect ty b ofs v)
          (CSharpMin_State f (make_memcpy dst src ty) k e le) m
          (CSharpMin_State f Sskip k e le) m'.
Proof.
  intros. inv H1; try congruence. 
  unfold make_memcpy. change le with (set_optvar None Vundef le) at 2. 
  exists b', ofs'. split; trivial.
  eapply csharpmin_effstep_sub_val.
  Focus 2. econstructor.
           econstructor. eauto. econstructor. eauto. constructor.  
           econstructor; eauto.  
           apply alignof_blockcopy_1248.
           apply sizeof_pos.  
           eapply Zdivide_trans. apply alignof_blockcopy_divides.
           apply sizeof_alignof_compat.
  intros.
 is related to builtins: need to define the builtin-effect 
              of memcpy to equal/imply the assign_loc effect*)
(*
Lemma make_store_correct:
  forall addr ty rhs code e le m b ofs v m' f k,
  make_store addr ty rhs = OK code ->
  eval_expr ge e le m addr (Vptr b ofs) ->
  eval_expr ge e le m rhs v ->
  assign_loc ty m b ofs v m' ->
  step ge (State f code k e le m) E0 (State f Sskip k e le m').
Proof.
  unfold make_store. intros until k; intros MKSTORE EV1 EV2 ASSIGN.
  inversion ASSIGN; subst.
  (* nonvolatile scalar *)
  rewrite H in MKSTORE; inv MKSTORE.
  econstructor; eauto. 
  (* by copy *)
  rewrite H in MKSTORE; inv MKSTORE. 
  eapply make_memcpy_correct; eauto. 
Qed.*)

Lemma make_store_correct:
  forall addr ty rhs code e le m b ofs v m' f k,
  make_store addr ty rhs = OK code ->
  eval_expr ge e le m addr (Vptr b ofs) ->
  eval_expr ge e le m rhs v ->
  assign_loc ty m b ofs v m' ->
  CSharpMin_corestep hf ge (CSharpMin_State f code k e le) m
                        (CSharpMin_State f Sskip k e le) m'.
Proof.
  unfold make_store. intros until k; intros MKSTORE EV1 EV2 ASSIGN.
  inversion ASSIGN; subst.
  (* nonvolatile scalar *)
  rewrite H in MKSTORE; inv MKSTORE.
  econstructor; eauto. 
  (* by copy *)
  rewrite H in MKSTORE; inv MKSTORE.
  (* We do not yet support external builtin [memcpy] *)
  eapply make_memcpy_correct; eauto. 
Qed.

Lemma make_store_correct_StoreEffect:
  forall addr ty rhs code e le m b ofs v m' f k,
  make_store addr ty rhs = OK code ->
  eval_expr ge e le m addr (Vptr b ofs) ->
  eval_expr ge e le m rhs v ->
  assign_loc ty m b ofs v m' ->
  match access_mode ty with
   By_value chunk =>
             effstep (csharpmin_eff_sem hf) ge 
                (StoreEffect (Vptr b ofs) (encode_val chunk v))
                (CSharpMin_State f code k e le) m
                (CSharpMin_State f Sskip k e le) m'
| By_copy => exists b' ofs', v = Vptr b' ofs' /\
             effstep (csharpmin_eff_sem hf) ge 
                (BuiltinEffect ge (EF_memcpy (sizeof ty) (alignof_blockcopy ty))
                                  (Vptr b ofs :: Vptr b' ofs' :: nil) m)
                (CSharpMin_State f code k e le) m
                (CSharpMin_State f Sskip k e le) m'
  | _ => False
  end.
Proof.
  unfold make_store. intros until k; intros MKSTORE EV1 EV2 ASSIGN.
  inversion ASSIGN; subst.
  (* nonvolatile scalar *)
  rewrite H in MKSTORE; inv MKSTORE.
  rewrite H. econstructor; eauto. 
  (* by copy *)
  rewrite H in MKSTORE; inv MKSTORE.
  rewrite H. 
  (* [memcpy] *)
   eapply make_memcpy_correct_BuiltinEffect; eauto.
Qed.

End CONSTRUCTORS.

(** * Basic preservation invariants *)

Section CORRECTNESS.

Variable prog: Clight.program.
Variable tprog: Csharpminor.program.
Hypothesis TRANSL: transl_program prog = OK tprog.

Let ge : Clight.genv := Genv.globalenv prog.
Let tge : Csharpminor.genv := Genv.globalenv tprog.

(*NEW*) Variable hf : I64Helpers.helper_functions.

Lemma symbols_preserved:
  forall s, Genv.find_symbol tge s = Genv.find_symbol ge s.
Proof (Genv.find_symbol_transf_partial2 transl_fundef transl_globvar _ TRANSL).

Lemma functions_translated:
  forall v f,
  Genv.find_funct ge v = Some f ->
  exists tf, Genv.find_funct tge v = Some tf /\ transl_fundef f = OK tf.
Proof (Genv.find_funct_transf_partial2 transl_fundef transl_globvar _ TRANSL).

Lemma function_ptr_translated:
  forall b f,
  Genv.find_funct_ptr ge b = Some f ->
  exists tf, Genv.find_funct_ptr tge b = Some tf /\ transl_fundef f = OK tf.
Proof (Genv.find_funct_ptr_transf_partial2 transl_fundef transl_globvar _ TRANSL).

Lemma var_info_translated:
  forall b v,
  Genv.find_var_info ge b = Some v ->
  exists tv, Genv.find_var_info tge b = Some tv /\ transf_globvar transl_globvar v = OK tv.
Proof (Genv.find_var_info_transf_partial2 transl_fundef transl_globvar _ TRANSL).

Lemma var_info_rev_translated:
  forall b tv,
  Genv.find_var_info tge b = Some tv ->
  exists v, Genv.find_var_info ge b = Some v /\ transf_globvar transl_globvar v = OK tv.
Proof (Genv.find_var_info_rev_transf_partial2 transl_fundef transl_globvar _ TRANSL).

Lemma block_is_volatile_preserved:
  forall b, block_is_volatile tge b = block_is_volatile ge b.
Proof.
  intros. unfold block_is_volatile.
  destruct (Genv.find_var_info ge b) eqn:?.
  exploit var_info_translated; eauto. intros [tv [A B]]. rewrite A. 
  unfold transf_globvar in B. monadInv B. auto.
  destruct (Genv.find_var_info tge b) eqn:?.
  exploit var_info_rev_translated; eauto. intros [tv [A B]]. congruence.
  auto.
Qed.

(*NEW: globalfunction_ptr_inject - just as in SelctionproofEFF.v*)
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

(** * Matching between environments *)

(** In this section, we define a matching relation between
  a Clight local environment and a Csharpminor local environment. *)


(*LENB: added parameter j - first, let's try an attempt where
   all offsets are 0*)
Record match_env (j:meminj) (e: Clight.env) (te: Csharpminor.env) : Prop :=
  mk_match_env {
    me_local:
      forall id b ty,
      e!id = Some (b, ty) -> exists b',
                             j b = Some(b',0) /\ te!id = Some(b', sizeof ty);
    me_local_inv:
      forall id b sz,
      te!id = Some (b, sz) -> exists b' ty,
                             j b' = Some(b,0) /\e!id = Some(b', ty)
  }.

Lemma match_env_inject_incr: forall j e te 
       (MENV : match_env j e te) j'
       (INC: inject_incr j j'),
     match_env j' e te.
Proof. intros.
  destruct MENV as [MENVa MENVb].
  split; intros.
    destruct (MENVa _ _ _ H) as [b' [J Eb]].
      apply INC in J.
      exists b'; split; trivial.
    destruct (MENVb _ _ _ H) as [b' [tp [J Eb]]].
      apply INC in J.
      exists b', tp; split; trivial.
Qed.

Lemma match_env_restrictD: forall j X e te 
       (MENV : match_env (restrict j X) e te),
     match_env j e te.
Proof. intros.
  eapply match_env_inject_incr; try eassumption.
  eapply restrict_incr.
Qed.

Lemma match_env_globals:
  forall j e te id,
  match_env j e te ->
  e!id = None ->
  te!id = None.
Proof.
  intros. destruct (te!id) as [[b sz] | ] eqn:?; auto.
  exploit me_local_inv; eauto. intros [b' [ty [J EQ]]]. congruence.
Qed.
(*
Lemma match_env_same_blocks:
  forall j e te,
  match_env j e te ->
  blocks_of_env te = Clight.blocks_of_env e.
Proof.
  intros.
  set (R := fun (x: (block * type)) (y: (block * Z)) =>
         match x, y with
         | (b1, ty), (b2, sz) => b2 = b1 /\ sz = sizeof ty
         end).
  assert (list_forall2 
            (fun i_x i_y => fst i_x = fst i_y /\ R (snd i_x) (snd i_y))
            (PTree.elements e) (PTree.elements te)).
  apply PTree.elements_canonical_order.
  intros id [b ty] GET. exists (b, sizeof ty); split. eapply me_local; eauto. red; auto.
  intros id [b sz] GET. exploit me_local_inv; eauto. intros [ty EQ].
  exploit me_local; eauto. intros EQ1. 
  exists (b, ty); split. auto. red; split; congruence.

  unfold blocks_of_env, Clight.blocks_of_env.
  generalize H0. induction 1. auto. 
  simpl. f_equal; auto.
  unfold block_of_binding, Clight.block_of_binding. 
  destruct a1 as [id1 [blk1 ty1]]. destruct b1 as [id2 [blk2 sz2]].
  simpl in *. destruct H1 as [A [B C]]. congruence.
Qed.
*)

Lemma match_env_same_blocks: forall j e te 
      (ENV: match_env j e te),
   list_forall2
      (fun (i_x : positive * (block * type)) (i_y : positive * (block * Z)) =>
               fst i_x = fst i_y /\
               j (fst (snd i_x)) = Some (fst (snd i_y), 0) /\
               snd (snd i_y) = sizeof (snd (snd i_x)))
  (PTree.elements e) (PTree.elements te).
Proof. intros. 
assert (HH1: forall (i : positive) (x : block * type),
     e ! i = Some x -> exists y : block * Z, te ! i = Some y /\ 
          j (fst x) = Some (fst y,0)
      /\ snd y = sizeof (snd x)).
  intros. destruct ENV. destruct x.
  destruct (me_local0 _ _ _ H) as [b' [J T]]. 
   exists (b', sizeof t). simpl. split; trivial. split; trivial.
assert(HH2: forall (i : positive) (y : block * Z),
  te ! i = Some y ->
  exists x : block * type, e ! i = Some x /\ j (fst x) = Some (fst y, 0) 
        /\ snd y = sizeof (snd x)).
  intros. destruct ENV. destruct y.
  destruct (me_local_inv0 _ _ _ H) as [b' [t [J T]]]. 
   exists (b', t). simpl. split; trivial. split; trivial.
   destruct (HH1 _ _ T) as [yy [TY [JY SZY]]].
   simpl in *. rewrite H in TY. inv TY. rewrite JY in J; inv J. simpl in *. trivial.  
apply (PTree.elements_canonical_order _ e te HH1 HH2).
Qed.

Lemma match_env_free_blocks_parallel_inject:
  forall e te m m' j tm
     (ENV: match_env j e te)
     (INJ: Mem.inject j m tm) 
     (FL: Mem.free_list m (Clight.blocks_of_env e) = Some m'),
  exists tm', Mem.free_list tm (blocks_of_env te) = Some tm' /\
              Mem.inject j m' tm'.
Proof. intros.
apply match_env_same_blocks in ENV.
clear - ENV FL INJ. 
unfold Clight.blocks_of_env in FL.
unfold blocks_of_env.
remember (PTree.elements e) as l; clear Heql.
remember (PTree.elements te) as tl; clear Heqtl.
generalize dependent tm.
generalize dependent m'.
generalize dependent m. clear - ENV.
induction ENV; simpl; intros.
  inv FL. exists tm. split; trivial.
remember (Clight.block_of_binding a1) as A1.
  unfold Clight.block_of_binding in HeqA1.
  destruct a1 as [id [b ty]]. subst. simpl in *.
  remember (Mem.free m b 0 (sizeof ty)) as d.
  destruct d; inv FL; apply eq_sym in Heqd.
  specialize (IHENV _ _ H1); clear H1.
  destruct b1 as [x [tb sizeT]].
  destruct H as [? [J SZ]]. simpl in *. subst. 
  destruct (free_parallel_inject _ _ _ _ _ _ _ INJ Heqd _ _ J)
   as [tm0 [FRT INJ0]].
  destruct (IHENV _ INJ0) as [tm' [FL' INJ']]; clear IHENV.
  exists tm'. simpl in *. rewrite Zplus_0_r in FRT.
  rewrite FRT. split; trivial.
Qed.

Lemma freelist_freelist_inject: forall m1 m1' j m2 e
        (FL1: Mem.free_list m1 (Clight.blocks_of_env e) = Some m1')
        (INJ : Mem.inject j m1 m2)
        te (MENV : match_env j e te)
        m2' 
        (FL2 : Mem.free_list m2 (blocks_of_env te) = Some m2'),
      Mem.inject j m1' m2'.
Proof. intros.
  destruct (match_env_free_blocks_parallel_inject _ _ _ _ _ _ MENV INJ FL1)
       as [tm [FL_tm Inj_tm]].
  rewrite FL_tm in FL2. inv FL2. assumption.
Qed.

Lemma FreelistEffect_PropagateLeft: forall
   m e m'
   (FL : Mem.free_list m (Clight.blocks_of_env e) = Some m')
   mu m2 (SMV : sm_valid mu m m2) (WD: SM_wd mu) 
   te (MENV: match_env (restrict (as_inj mu) (vis mu)) e te)
   b2 ofs
   (EFF : FreelistEffect m2 (blocks_of_env te) b2 ofs = true)
   (LB: locBlocksTgt mu b2 = false),
  exists b1 delta,
    foreign_of mu b1 = Some (b2, delta) /\
    FreelistEffect m (Clight.blocks_of_env e) b1 (ofs - delta) = true /\
    Mem.perm m b1 (ofs - delta) Max Nonempty.
Proof. intros.
apply match_env_same_blocks in MENV.
clear - MENV FL SMV EFF LB WD. 
unfold Clight.blocks_of_env in FL.
unfold Clight.blocks_of_env.
unfold blocks_of_env in EFF.
remember (PTree.elements e) as l; clear Heql.
remember (PTree.elements te) as tl; clear Heqtl.
generalize dependent m2.
generalize dependent m'.
generalize dependent m. clear - MENV LB WD.
induction MENV; simpl; intros.
  intuition.
destruct a1 as [x [b tp]].
destruct b1 as [id [b' z]].
simpl in *.
destruct H as [? [Rb ?]]; subst.
remember (Mem.free m b 0 (sizeof tp)) as d.
destruct d; inv FL; apply eq_sym in Heqd.
apply orb_true_iff in EFF.
destruct EFF as [EFF | EFF].
  specialize (IHMENV _ _ H0).
  assert (SMV': sm_valid mu m0 m2).
    split; intros.
      eapply (Mem.valid_block_free_1 _ _ _ _ _ Heqd).
        eapply SMV; eassumption.
        eapply SMV; eassumption.
  destruct (IHMENV _ SMV' EFF) as [b1 [delta [Frg [FL2 P]]]].
  exists b1, delta; intuition.
    apply orb_true_iff; left.
      remember (map Clight.block_of_binding al) as t.
         clear - Heqd FL2. generalize dependent m0. generalize dependent m.
         induction t; simpl; intros. assumption.
         destruct a as [[bb lo] hi].
         apply orb_true_iff in FL2.
         apply orb_true_iff.
         destruct FL2. apply (IHt _ _ Heqd) in H. left; trivial.
         right. clear IHt. unfold FreeEffect. unfold FreeEffect in H.
         destruct (valid_block_dec m0 b1).
           destruct (valid_block_dec m b1); trivial.
           apply (Mem.valid_block_free_2 _ _ _ _ _ Heqd) in v. contradiction.
         inv H.
    eapply Mem.perm_free_3; eassumption.
destruct (restrictD_Some _ _ _ _ _ Rb).
  destruct (FreeEffect_PropagateLeft _ _ _ _ _ Heqd _ _ SMV WD _ H H1 _ _ EFF LB)
    as [b1 [delta [Frg [EFF1 P1]]]].
  exists b1, delta. rewrite EFF1. intuition.
Qed.
  
Lemma match_env_empty: forall j,
  match_env j Clight.empty_env Csharpminor.empty_env.
Proof.
  unfold Clight.empty_env, Csharpminor.empty_env.
  constructor.
  intros until ty. repeat rewrite PTree.gempty. congruence.
  intros until sz. rewrite PTree.gempty. congruence.
Qed.
(*
Lemma match_env_empty:
  match_env Clight.empty_env Csharpminor.empty_env.
Proof.
  unfold Clight.empty_env, Csharpminor.empty_env.
  constructor.
  intros until ty. repeat rewrite PTree.gempty. congruence.
  intros until sz. rewrite PTree.gempty. congruence.
Qed.
*)
(** The following lemmas establish the [match_env] invariant at
  the beginning of a function invocation, after allocation of
  local variables and initialization of the parameters. *)

Lemma match_env_alloc_variables:
  forall vars e1 m1 e2 m2,
  Clight.alloc_variables e1 m1 vars e2 m2 ->
  forall mu te1 tm1,
  match_env (restrict (as_inj mu) (vis mu)) e1 te1 ->
  Mem.inject (as_inj mu) m1 tm1 ->
  SM_wd mu -> sm_valid mu m1 tm1 -> 
  exists te2 tm2 mu',
  Csharpminor.alloc_variables te1 tm1 (map transl_var vars) te2 tm2
  /\ match_env (restrict (as_inj mu') (vis mu')) e2 te2 /\ Mem.inject (as_inj mu') m2 tm2
  /\ intern_incr mu mu'
  /\ sm_inject_separated mu mu' m1 tm1
  /\ sm_locally_allocated mu mu' m1 tm1 m2 tm2 
  /\ SM_wd mu' /\ sm_valid mu' m2 tm2
  /\ (REACH_closed m1 (vis mu) -> REACH_closed m2 (vis mu')).
Proof. intros vars.
  induction vars; intros; simpl; inv H. 
  exists te1, tm1, mu. intuition.
       constructor. 
       apply intern_incr_refl.
       apply sm_inject_separated_same_sminj.
       apply sm_locally_allocatedChar.
         repeat split; extensionality b; 
         try rewrite freshloc_irrefl; intuition.
  specialize (IHvars _ _ _ _ H11). 
  exploit (alloc_parallel_intern mu); try eassumption. apply Zle_refl. apply Zle_refl. 
  intros [mu0 [tm0 [b2 [Alloc2 [INJ0 [IntInc0 [A [B [C [D [E [F G]]]]]]]]]]]].
  assert (VisB1: vis mu0 b1 = true).
         assert (DomSrc mu0 b1 = true).
           eapply as_inj_DomRng; eassumption.
         unfold DomSrc in H. unfold vis.
         remember (locBlocksSrc mu0 b1) as d.
         destruct d; simpl in *; trivial.
         assert (extBlocksSrc mu = extBlocksSrc mu0) by eapply IntInc0.
         rewrite <- H4 in H.
         elim (Mem.fresh_block_alloc _ _ _ _ _ H8).
         eapply H3. unfold DOM, DomSrc. intuition.
  assert (MENV0 :match_env (restrict (as_inj mu0) (vis mu0))
                    (PTree.set id (b1, ty) e1)
                    (PTree.set id (b2, sizeof ty) te1)).
    clear IHvars.
    constructor.
    (* me_local *)
    intros until ty0. repeat rewrite PTree.gsspec.
    destruct (peq id0 id); intros. inv H.
       exists b2; split; trivial.
         eapply restrictI_Some; assumption.
      destruct (me_local _ _ _ H0 _ _ _ H) as [b' [AI TE]].
       exists b'; split; trivial.
       eapply intern_incr_restrict; eassumption.
    (* me_local_inv *)
    intros until sz. repeat rewrite PTree.gsspec. 
    destruct (peq id0 id); intros.
      inv H. exists b1, ty; split; trivial.
        apply restrictI_Some; trivial.
      destruct (me_local_inv _ _ _ H0 _ _ _ H) as [b' [tp [AI TE]]].
       exists b', tp; split; trivial.
       eapply intern_incr_restrict; eassumption.
  destruct (IHvars mu0 _ _ MENV0 INJ0 E F) 
    as [te2 [tm2 [mu' [AVars' [MENV' [INJ' [IntInc' 
        [SEP' [LAC' [WD' [VAL' RC']]]]]]]]]]]. 
  simpl.
  exists te2, tm2, mu'. intuition.
    econstructor; eassumption.
    eapply intern_incr_trans; eassumption.
    eapply intern_separated_incr_fwd2; try eassumption.
      eapply alloc_forward; eassumption.
      eapply alloc_forward; eassumption.
    eapply sm_locally_allocated_trans; try eassumption.
      eapply alloc_forward; eassumption.
      eapply Clight_coop.alloc_variables_forward; try eassumption.
      eapply alloc_forward; eassumption.
      eapply alloc_variables_forward; try eassumption.
Qed.
(*
Lemma match_env_alloc_variables:
  forall e1 m1 vars e2 m2,
  Clight.alloc_variables e1 m1 vars e2 m2 ->
  forall te1,
  match_env e1 te1 ->
  exists te2,
  Csharpminor.alloc_variables te1 m1 (map transl_var vars) te2 m2
  /\ match_env e2 te2.
Proof.
  induction 1; intros; simpl.
  exists te1; split. constructor. auto.
  exploit (IHalloc_variables (PTree.set id (b1, sizeof ty) te1)).
  constructor.
    (* me_local *)
    intros until ty0. repeat rewrite PTree.gsspec.
    destruct (peq id0 id); intros. congruence. eapply me_local; eauto. 
    (* me_local_inv *)
    intros until sz. repeat rewrite PTree.gsspec. 
    destruct (peq id0 id); intros. exists ty; congruence. eapply me_local_inv; eauto. 
  intros [te2 [ALLOC MENV]].
  exists te2; split. econstructor; eauto. auto.
Qed. *)

Definition match_tempenv (j:meminj) (le: temp_env) (tle: Csharpminor.temp_env) :=
  forall id v, le!id = Some v ->
  exists tv, val_inject j v tv /\ tle!id = Some tv.

Lemma match_tempenv_inject_incr: forall j e te 
       (TENV : match_tempenv j e te) j'
       (INC: inject_incr j j'),
     match_tempenv j' e te.
Proof. red; intros.
  destruct (TENV _ _ H) as [v' [V' Tv']].
  exists v'; split; trivial.
  eapply val_inject_incr; eassumption. 
Qed.

Lemma match_tempenv_set: forall j le tle
      (TENV : match_tempenv j le tle) v tv
      (Inj : val_inject j v tv) x,
     match_tempenv j (PTree.set x v le) (PTree.set x tv tle).
Proof. intros.
  red; intros.
  rewrite PTree.gsspec in H.
  rewrite PTree.gsspec.
  destruct (peq id x); subst.
    inv H. exists tv; split; trivial.
  apply (TENV _ _ H).
Qed.

Lemma create_undef_temps_match:
  forall temps,
  create_undef_temps (map fst temps) = Clight.create_undef_temps temps.
Proof.
  induction temps; simpl. auto. 
  destruct a as [id ty]. simpl. decEq. auto.
Qed.
Lemma create_undef_temps_match_inject:
  forall temps j,
  match_tempenv j (Clight.create_undef_temps temps)
                  (create_undef_temps (map fst temps)).
Proof.
  induction temps; simpl. intros. 
     red; intros. 
     rewrite PTree.gempty in H; discriminate.
  intros. 
    destruct a as [id ty]. simpl.
    red; intros.
      rewrite PTree.gsspec in H. rewrite PTree.gsspec.
      destruct (peq id0 id); subst.
        inv H. exists Vundef; split; trivial.
      apply (IHtemps j id0 _ H).
Qed.

Lemma bind_parameter_temps_match_inject:
  forall vars vals le1 le2
  (BP: Clight.bind_parameter_temps vars vals le1 = Some le2)
  j tle1 (TENV: match_tempenv j le1 tle1)
  tvals (Inj: val_list_inject j vals tvals),
  exists tle2,
    bind_parameters (map fst vars) tvals tle1 = Some tle2 /\
    match_tempenv j le2 tle2.
Proof.
  induction vars; simpl; intros.
  destruct vals; inv BP. inv Inj.
    exists tle1; split; trivial.
  destruct a as [id ty]. destruct vals; try discriminate.
    inv Inj.
    assert (TE:= match_tempenv_set _ _ _ TENV _ _ H1 id).
    apply (IHvars _ _ _ BP _ _ TE _ H3).
Qed.
(*
Lemma bind_parameter_temps_match:
  forall vars vals le1 le2,
  Clight.bind_parameter_temps vars vals le1 = Some le2 ->
  bind_parameters (map fst vars) vals le1 = Some le2.
Proof.
  induction vars; simpl; intros.
  destruct vals; inv H. auto. 
  destruct a as [id ty]. destruct vals; try discriminate. auto. 
Qed.
*)
(** * Proof of semantic preservation *)

(** ** Semantic preservation for expressions *)

(** The proof of semantic preservation for the translation of expressions
  relies on simulation diagrams of the following form:
<<
         e, le, m, a ------------------- te, le, m, ta
            |                                |
            |                                |
            |                                |
            v                                v
         e, le, m, v ------------------- te, le, m, v
>>
  Left: evaluation of r-value expression [a] in Clight.
  Right: evaluation of its translation [ta] in Csharpminor.
  Top (precondition): matching between environments [e], [te], 
    plus well-typedness of expression [a].
  Bottom (postcondition): the result values [v] 
    are identical in both evaluations.

  We state these diagrams as the following properties, parameterized
  by the Clight evaluation. *)


Lemma unary_op_inject: forall op v ty u 
           (SUO:sem_unary_operation op v ty = Some u)
           j tv (V: val_inject j v tv),
      val_inject j u u /\ sem_unary_operation op tv ty = Some u.
Proof. intros.
  destruct op; simpl in *.
  rewrite notbool_bool_val in *.
    remember (bool_val v ty) as q; apply eq_sym in Heqq.
    destruct q; inv SUO.
    split. apply val_inject_of_bool.
     rewrite (bool_val_inject  _ _ _ _ _ Heqq V). trivial.
  unfold sem_notint in *.
    remember (classify_notint ty) as q; apply eq_sym in Heqq.
    destruct q; inv SUO.
    destruct v; inv H0. inv V.
      split. constructor. trivial.
    destruct v; inv H0. inv V.
      split. constructor. trivial.
  unfold sem_neg in *.
    remember (classify_neg ty) as q; apply eq_sym in Heqq.
    destruct q; inv SUO.
    destruct v; inv H0. inv V.
      split. constructor. trivial.
    destruct v; inv H0. inv V.
      split. constructor. trivial.
    destruct v; inv H0. inv V.
      split. constructor. trivial.
Qed.

Lemma unary_op_inject': forall op v ty u 
           (SUO:sem_unary_operation op v ty = Some u)
           j tv (V: val_inject j v tv),
      exists tu, val_inject j u tu /\ 
        sem_unary_operation op tv ty = Some tu.
Proof. intros.
  exists u. eapply unary_op_inject; eassumption.
Qed.

Lemma binary_op_inject: forall op v1 v2 ty1 ty2 m u 
           (SBO:sem_binary_operation op v1 ty1 v2 ty2 m = Some u)
           j tm (MINJ : Mem.inject j m tm) 
           tv1 (V1: val_inject j v1 tv1) tv2 (V2: val_inject j v2 tv2),
      exists tu, 
           sem_binary_operation op tv1 ty1 tv2 ty2 tm = Some tu
           /\ val_inject j u tu.
Proof. intros.
eapply sem_binary_operation_inj; try eassumption.
  intros. eapply Mem.valid_pointer_inject_val; try eassumption.
          econstructor. eassumption. trivial.
  intros. eapply Mem.weak_valid_pointer_inject_val; try eassumption.
          econstructor. eassumption. trivial.
  intros. eapply Mem.weak_valid_pointer_inject_no_overflow; try eassumption.
  intros. eapply Mem.different_pointers_inject; try eassumption.
Qed. 

Section EXPR.

Variable e: Clight.env.
Variable le: temp_env.
Variable m: mem.
Variable tm: mem. (*Lenb: NEW*)
Variable te: Csharpminor.env.
Variable tle: Csharpminor.temp_env. (*Lenb: NEW*)
Variable j: meminj. (*Lenb: NEW*)
Hypothesis MENV: match_env j e te.
Hypothesis LENV: match_tempenv j le tle. (*Lenb: NEW*)
Hypothesis MINJ: Mem.inject j m tm. (*Lenb: NEW*)
Hypothesis PG: meminj_preserves_globals ge j. (*Lenb: NEW*)

Lemma deref_loc_inject: forall ty b ofs v 
        (D:deref_loc ty m b ofs v) tb delta
        (J: j b = Some(tb,delta)),
      exists tv, val_inject j v tv /\
         deref_loc ty tm tb (Int.add ofs (Int.repr delta)) tv.
Proof. intros.
  inv D.
(*case deref_loc_value*)
  assert (val_inject j (Vptr b ofs) (Vptr tb (Int.add ofs (Int.repr delta)))).
    econstructor. eassumption. trivial.
  destruct (Mem.loadv_inject _ _ _ _ _ _ _ MINJ H0 H1) as [tv [TLDV VI]].
  exists tv; split; trivial.
  eapply (deref_loc_value); eassumption.
(*case deref_loc_reference*)
  eexists; split. econstructor. eassumption. reflexivity.
  eapply (deref_loc_reference); assumption.
(*case deref_loc_reference*)
  eexists; split. econstructor. eassumption. reflexivity.
  eapply (deref_loc_copy); assumption.
Qed.

Lemma transl_expr_lvalue_correct:
  (forall a v,
   Clight.eval_expr ge e le m a v ->
   forall ta (TR: transl_expr a = OK ta),
   exists tv, val_inject j v tv /\
   Csharpminor.eval_expr tge te tle tm ta tv)
/\(forall a b ofs,
   Clight.eval_lvalue ge e le m a b ofs ->
   forall ta (TR: transl_lvalue a = OK ta),
   exists tv, val_inject j (Vptr b ofs) tv /\
   Csharpminor.eval_expr tge te tle tm ta tv).
Proof.
  apply eval_expr_lvalue_ind; intros; try (monadInv TR).
(* const int *)
  eexists. split. econstructor.
  apply make_intconst_correct.
(* const float *)
  eexists. split. econstructor.
  apply make_floatconst_correct.
(* const long *)
  eexists. split. econstructor.
  apply make_longconst_correct.
(* temp var *)
  destruct (LENV _ _ H) as [tv [? ?]].
  exists tv; split; trivial.
  constructor; auto.
(* addrof *)
  inv TR. auto.
(* unop *)
  destruct (H0 _ EQ) as [tv [VI EE]]; clear H0 EQ.
  destruct (unary_op_inject _ _ _ _ H1 _ _ VI); clear H1 VI.
  exists v; split; trivial. 
  eapply transl_unop_correct; eauto.
(* binop *)
  destruct (H0 _ EQ) as [tv1 [VI1 EE1]]; clear H0 EQ.
  destruct (H2 _ EQ1) as [tv2 [VI2 EE2]]; clear H2 EQ1.
  destruct (binary_op_inject _ _ _ _ _ _ _ H3 _ _ MINJ _ VI1 _ VI2) 
   as [tv [TV ETV]]; clear H3 VI1 VI2.
  exists tv; split; trivial. 
  eapply transl_binop_correct; eauto.
(* cast *)
  destruct (H0 _ EQ) as [tv1 [TV1 ET1]]. clear H0.
  destruct (sem_cast_inject _ _ _ _ _ _ H1 TV1) as [tv [SC VI]].
  exists tv; split; trivial.
  apply (make_cast_correct _ _ _ _ _ _ _ _ _ _ EQ0 ET1 SC).
(* rvalue out of lvalue *)
  exploit transl_expr_lvalue; eauto. intros [tb [TRLVAL MKLOAD]].
  destruct (H0 _ TRLVAL) as [tv [VT ET]]; clear H0.
  inv VT.
  destruct (deref_loc_inject _ _ _ _ H1 _ _ H3) as [tv [InjTv DerefTv]]. 
  specialize (make_load_correct tge tb (typeof a) ta b2 (Int.add ofs (Int.repr delta)) _ _ _ _ MKLOAD ET DerefTv).
  intros.
  exists tv; split; eassumption.
(* var local *)
  destruct (me_local _ _ _ MENV _ _ _ H) as [tb [J TH]].
   eexists; split; econstructor. eassumption. reflexivity.
   eapply eval_var_addr_local; eassumption.
(* var global *)
  exists (Vptr l Int.zero); split.
  econstructor.
  eapply (meminj_preserves_globals_isGlobalBlock _ _ PG).
  eapply find_symbol_isGlobal; eassumption.
  rewrite Int.add_zero. trivial. 
  econstructor.
    eapply eval_var_addr_global.  
    eapply match_env_globals; eauto.
    rewrite symbols_preserved. eassumption.
(* deref *)
  auto.
(* field struct *)
  simpl in TR. rewrite H1 in TR. monadInv TR.
  destruct (H0 _ EQ) as [tv [VT ET]]; clear H0.
  inv VT. 
  eexists; split. econstructor. eassumption. reflexivity.
  eapply eval_Ebinop; eauto.
  apply make_intconst_correct.
  rewrite EQ1 in H2. inv H2. 
  simpl. rewrite Int.add_assoc. rewrite Int.add_assoc. 
         rewrite (Int.add_commut (Int.repr delta0)). trivial. 
(* field union *)
  simpl in TR. rewrite H1 in TR. eauto.
Qed.
(*
Lemma transl_expr_lvalue_correct:
  (forall a v,
   Clight.eval_expr ge e le m a v ->
   forall ta (TR: transl_expr a = OK ta)
          tv (TV: val_inject j v tv),
   Csharpminor.eval_expr tge te tle tm ta tv)
/\(forall a b ofs,
   Clight.eval_lvalue ge e le m a b ofs ->
   forall ta (TR: transl_lvalue a = OK ta)
          tv (TV: val_inject j (Vptr b ofs) tv),
   Csharpminor.eval_expr tge te le m ta tv).
Proof.
  apply eval_expr_lvalue_ind; intros; try (monadInv TR).
(* const int *)
  inv TV.
  apply make_intconst_correct.
(* const float *)
  inv TV.
  apply make_floatconst_correct.
(* const long *)
  inv TV.
  apply make_longconst_correct.
(* temp var *)
  constructor; auto.  assumption.
(* temp var *)
  constructor; auto.
(* addrof *)
  destruct (MENV _ _ H). 
  simpl in TR. auto. 
(* unop *)
  eapply transl_unop_correct; eauto.
(* binop *)
  eapply transl_binop_correct; eauto.
(* cast *)
  eapply make_cast_correct; eauto.
(* rvalue out of lvalue *)
  exploit transl_expr_lvalue; eauto. intros [tb [TRLVAL MKLOAD]].
  eapply make_load_correct; eauto.  
(* var local *)
  exploit (me_local _ _ MENV); eauto. intros EQ.
  econstructor. eapply eval_var_addr_local. eauto.
(* var global *)
  econstructor. eapply eval_var_addr_global. 
  eapply match_env_globals; eauto.
  rewrite symbols_preserved. auto.
(* deref *)
  simpl in TR. eauto. 
(* field struct *)
  simpl in TR. rewrite H1 in TR. monadInv TR.
  eapply eval_Ebinop; eauto.
  apply make_intconst_correct. 
  simpl. congruence.
(* field union *)
  simpl in TR. rewrite H1 in TR. eauto.
Qed.
*)

Lemma transl_expr_correct: forall a v,
       Clight.eval_expr ge e le m a v ->
       forall ta, transl_expr a = OK ta ->
       exists tv, val_inject j v tv /\ 
            eval_expr tge te tle tm ta tv.
Proof (proj1 transl_expr_lvalue_correct).
(*
Lemma transl_expr_correct: forall a v,
   Clight.eval_expr ge e le m a v ->
   forall ta, transl_expr a = OK ta ->
   Csharpminor.eval_expr tge te le m ta v.
Proof (proj1 transl_expr_lvalue_correct).
*)

Lemma transl_lvalue_correct:
   forall a b ofs, 
       eval_lvalue ge e le m a b ofs ->
       forall ta, transl_lvalue a = OK ta ->
       exists tv, val_inject j (Vptr b ofs) tv /\
                   eval_expr tge te tle tm ta tv.
Proof (proj2 transl_expr_lvalue_correct).
(*
Lemma transl_lvalue_correct:
   forall a b ofs,
   Clight.eval_lvalue ge e le m a b ofs ->
   forall ta, transl_lvalue a = OK ta ->
   Csharpminor.eval_expr tge te le m ta (Vptr b ofs).
Proof (proj2 transl_expr_lvalue_correct).
*)
Lemma transl_arglist_correct:
  forall al tyl vl,
  Clight.eval_exprlist ge e le m al tyl vl ->
  forall tal, transl_arglist al tyl = OK tal ->
  exists tvl, val_list_inject j vl tvl /\
  Csharpminor.eval_exprlist tge te tle tm tal tvl.
Proof.
  induction 1; intros.
  monadInv H. exists nil. split; constructor.
  monadInv H2.
  destruct (IHeval_exprlist _ EQ0) as [tv1 [VT ET]]; clear IHeval_exprlist.
  destruct (transl_expr_correct _ _ H _ EQ) as [? [? ?]].
  destruct (sem_cast_inject _ _ _ _ _ _ H0 H2) as [? [? ?]].
  specialize (make_cast_correct _ _ _ _ _ _ _ _ _ _ EQ1 H3 H4). intros.
  eexists; split. econstructor; eassumption.
  econstructor; eassumption.  
Qed.
(*
Lemma transl_arglist_correct:
  forall al tyl vl,
  Clight.eval_exprlist ge e le m al tyl vl ->
  forall tal, transl_arglist al tyl = OK tal ->
  Csharpminor.eval_exprlist tge te le m tal vl.
Proof.
  induction 1; intros.
  monadInv H. constructor.
  monadInv H2. constructor. 
  eapply make_cast_correct; eauto. eapply transl_expr_correct; eauto. auto. 
Qed.
*)

Lemma make_boolean_inject:
 forall a v ty b,
  Clight.eval_expr ge e le m a v ->
  bool_val v ty = Some b ->
  forall ta, transl_expr a = OK ta ->
  exists tv,
    Csharpminor.eval_expr tge te tle tm (make_boolean ta ty) tv
    /\ Val.bool_of_val tv b.
Proof.
  intros. unfold make_boolean. unfold bool_val in H0. 
  destruct (classify_bool ty); destruct v; inv H0.
(* int *)
  destruct (transl_expr_correct _ _ H _ H1) as [tv [Vinj ET]].
  inv Vinj. 
  eexists; split. apply make_cmp_ne_zero_correct with (n := i); auto.
  destruct (Int.eq i Int.zero); simpl; constructor.
(* float *)
  destruct (transl_expr_correct _ _ H _ H1) as [tv [Vinj ET]].
  inv Vinj. 
  econstructor; split. econstructor; eauto. econstructor. reflexivity.
   simpl. reflexivity.
  unfold Val.cmpf, Val.cmpf_bool. 
  rewrite <- Float.cmp_ne_eq.
  destruct (Float.cmp Cne f Float.zero); constructor. 
(* pointer *)
  destruct (transl_expr_correct _ _ H _ H1) as [tv [Vinj ET]].
  inv Vinj. 
  econstructor; split. econstructor; eauto. econstructor; reflexivity. reflexivity.
  unfold Val.cmpu, Val.cmpu_bool. simpl. 
  destruct (Int.eq i Int.zero); simpl; constructor. 

  destruct (transl_expr_correct _ _ H _ H1) as [tv [Vinj ET]].
  inv Vinj. 
  exists Vtrue; split. econstructor; eauto. constructor; reflexivity.
     simpl. unfold Val.cmpu, Val.cmpu_bool. simpl. 
  destruct (Int.eq i Int.zero); simpl; constructor. 
  constructor.   
(* long *)
  destruct (transl_expr_correct _ _ H _ H1) as [tv [Vinj ET]].
  inv Vinj. 
  econstructor; split. econstructor; eauto. constructor; reflexivity.
  simpl. unfold Val.cmpl. simpl. eauto. 
  destruct (Int64.eq i Int64.zero); simpl; constructor. 
Qed.

End EXPR.

(** ** Semantic preservation for statements *)

(** The simulation diagram for the translation of statements and functions
  is a "plus" diagram of the form
<<
           I
     S1 ------- R1
     |          | 
   t |        + | t
     v          v  
     S2 ------- R2
           I                         I
>>

The invariant [I] is the [match_states] predicate that we now define.
*)

Inductive match_transl: stmt -> cont -> stmt -> cont -> Prop :=
  | match_transl_0: forall ts tk,
      match_transl ts tk ts tk
  | match_transl_1: forall ts tk,
      match_transl (Sblock ts) tk ts (Kblock tk).
(*
Lemma match_transl_step:
  forall ts tk ts' tk' f te le m,
  match_transl (Sblock ts) tk ts' tk' ->
  star (clight_corestep tge (CL_core f ts' tk' te le) m E0 (State f ts (Kblock tk) te le m).
Proof.
  intros. inv H. 
  apply star_one. constructor. 
  apply star_refl.
Qed.
*)

Lemma match_transl_corestep:
  forall ts tk ts' tk' f te le m,
  match_transl (Sblock ts) tk ts' tk' ->
  corestep_star (csharpmin_eff_sem hf)  tge 
       (CSharpMin_State f ts' tk' te le) m
       (CSharpMin_State f ts (Kblock tk) te le) m.
Proof.
  intros. inv H. 
  apply corestep_star_one. constructor. 
  apply corestep_star_zero.
Qed.

Lemma match_transl_effstep:
  forall ts tk ts' tk' f te le m,
  match_transl (Sblock ts) tk ts' tk' ->
  effstep_star (csharpmin_eff_sem hf)  tge EmptyEffect
       (CSharpMin_State f ts' tk' te le) m
       (CSharpMin_State f ts (Kblock tk) te le) m.
Proof.
  intros. inv H. 
  apply effstep_star_one. constructor. 
  apply effstep_star_zero.
Qed.

Inductive match_cont (j:meminj): type -> nat -> nat -> Clight.cont -> Csharpminor.cont -> Prop :=
  | match_Kstop: forall tyret nbrk ncnt,
      match_cont j tyret nbrk ncnt Clight.Kstop Kstop
  | match_Kseq: forall tyret nbrk ncnt s k ts tk,
      transl_statement tyret nbrk ncnt s = OK ts ->
      match_cont j tyret nbrk ncnt k tk ->
      match_cont j tyret nbrk ncnt
                 (Clight.Kseq s k)
                 (Kseq ts tk)
  | match_Kloop1: forall tyret s1 s2 k ts1 ts2 nbrk ncnt tk,
      transl_statement tyret 1%nat 0%nat s1 = OK ts1 ->
      transl_statement tyret 0%nat (S ncnt) s2 = OK ts2 ->
      match_cont j tyret nbrk ncnt k tk ->
      match_cont j tyret 1%nat 0%nat
                   (Clight.Kloop1 s1 s2 k)
                   (Kblock (Kseq ts2 (Kseq (Sloop (Sseq (Sblock ts1) ts2)) (Kblock tk))))
  | match_Kloop2: forall tyret s1 s2 k ts1 ts2 nbrk ncnt tk,
      transl_statement tyret 1%nat 0%nat s1 = OK ts1 ->
      transl_statement tyret 0%nat (S ncnt) s2 = OK ts2 ->
      match_cont j tyret nbrk ncnt k tk ->
      match_cont j tyret 0%nat (S ncnt)
                 (Clight.Kloop2 s1 s2 k)
                 (Kseq (Sloop (Sseq (Sblock ts1) ts2)) (Kblock tk))
  | match_Kswitch: forall tyret nbrk ncnt k tk,
      match_cont j tyret nbrk ncnt k tk ->
      match_cont j tyret 0%nat (S ncnt)
                   (Clight.Kswitch k)
                   (Kblock tk)
  | match_Kcall_some: forall tyret nbrk ncnt nbrk' ncnt' f e k id tf te le tle tk,
      transl_function f = OK tf ->
      match_env j e te ->
      match_tempenv j le tle ->
      match_cont j (Clight.fn_return f) nbrk' ncnt' k tk ->
      match_cont j tyret nbrk ncnt 
                 (Clight.Kcall id f e le k)
                 (Kcall id tf te tle tk).

Lemma match_cont_inject_incr: forall j j' (I: inject_incr j j') tp n m k k'
        (MC: match_cont j tp n m k k'), match_cont j' tp n m k k'.
Proof. intros.
  induction MC; try (econstructor; try eassumption).
  eapply match_env_inject_incr; eassumption.
  eapply match_tempenv_inject_incr; eassumption. 
Qed.

Inductive match_states (j:meminj) : CL_core -> mem -> CSharpMin_core -> mem -> Prop :=
  | match_state:
      forall f nbrk ncnt s k e le m tf ts tk te tle ts' tk' tm
          (TRF: transl_function f = OK tf)
          (TR: transl_statement (Clight.fn_return f) nbrk ncnt s = OK ts)
          (MTR: match_transl ts tk ts' tk')
          (MENV: match_env j e te)
          (TENV: match_tempenv j le tle)
          (MK: match_cont j (Clight.fn_return f) nbrk ncnt k tk),
      match_states j (CL_State f s k e le) m
                   (CSharpMin_State tf ts' tk' te tle) tm
  | match_callstate:
      forall fd args1 k m tfd tk targs tres tm args2
          (TR: transl_fundef fd = OK tfd)
          (MK: match_cont j Tvoid 0%nat 0%nat k tk)
          (ISCC: Clight.is_call_cont k)
          (TY: type_of_fundef fd = Tfunction targs tres)
           (ArgsInj: val_list_inject j args1 args2),
      match_states j (CL_Callstate fd args1 k) m
                   (CSharpMin_Callstate tfd args2 tk) tm
  | match_returnstate:
      forall res1 res2 k m tk tm
          (MK: match_cont j Tvoid 0%nat 0%nat k tk)
          (Vinj: val_inject j res1 res2),
      match_states j (CL_Returnstate res1 k) m
                   (CSharpMin_Returnstate res2 tk) tm.

Remark match_states_skip:
  forall j f e le te tle nbrk ncnt k tf tk m tm,
  transl_function f = OK tf ->
  match_env j e te ->
  match_tempenv j le tle ->
  match_cont j (Clight.fn_return f) nbrk ncnt k tk ->
  match_states j (CL_State f Clight.Sskip k e le) m (CSharpMin_State tf Sskip tk te tle) tm.
Proof.
  intros. econstructor; eauto. simpl; reflexivity. constructor.  
Qed.

(** Commutation between label resolution and compilation *)

Section FIND_LABEL.
Variable lbl: label.
Variable tyret: type.

Lemma transl_find_label:
  forall s j nbrk ncnt k ts tk
  (TR: transl_statement tyret nbrk ncnt s = OK ts)
  (MC: match_cont j tyret nbrk ncnt k tk),
  match Clight.find_label lbl s k with
  | None => find_label lbl ts tk = None
  | Some (s', k') =>
      exists ts', exists tk', exists nbrk', exists ncnt',
      find_label lbl ts tk = Some (ts', tk')
      /\ transl_statement tyret nbrk' ncnt' s' = OK ts'
      /\ match_cont j tyret nbrk' ncnt' k' tk'
  end

with transl_find_label_ls:
  forall ls j nbrk ncnt k tls tk
  (TR: transl_lbl_stmt tyret nbrk ncnt ls = OK tls)
  (MC: match_cont j tyret nbrk ncnt k tk),
  match Clight.find_label_ls lbl ls k with
  | None => find_label_ls lbl tls tk = None
  | Some (s', k') =>
      exists ts', exists tk', exists nbrk', exists ncnt',
      find_label_ls lbl tls tk = Some (ts', tk')
      /\ transl_statement tyret nbrk' ncnt' s' = OK ts'
      /\ match_cont j tyret nbrk' ncnt' k' tk'
  end.

Proof.
  intros s; case s; intros; try (monadInv TR); simpl.
(* skip *)
  auto.
(* assign *)
  unfold make_store, make_memcpy in EQ3.
  destruct (access_mode (typeof e)); inv EQ3; auto.
(* set *)
  auto.
(* call *)
  simpl in TR. destruct (classify_fun (typeof e)); monadInv TR. auto.
(* builtin *)
  auto.
(* seq *)
  exploit (transl_find_label s0 j nbrk ncnt (Clight.Kseq s1 k)); eauto. constructor; eauto. 
  destruct (Clight.find_label lbl s0 (Clight.Kseq s1 k)) as [[s' k'] | ].
  intros [ts' [tk' [nbrk' [ncnt' [A [B C]]]]]].
  rewrite A. exists ts'; exists tk'; exists nbrk'; exists ncnt'; auto.
  intro. rewrite H. eapply transl_find_label; eauto.
(* ifthenelse *)
  exploit (transl_find_label s0); eauto. 
  destruct (Clight.find_label lbl s0 k) as [[s' k'] | ].
  intros [ts' [tk' [nbrk' [ncnt' [A [B C]]]]]].
  rewrite A. exists ts'; exists tk'; exists nbrk'; exists ncnt'; auto.
  intro. rewrite H. eapply transl_find_label; eauto.
(* loop *)
  exploit (transl_find_label s0 j 1%nat 0%nat (Kloop1 s0 s1 k)); eauto. econstructor; eauto.
  destruct (Clight.find_label lbl s0 (Kloop1 s0 s1 k)) as [[s' k'] | ].
  intros [ts' [tk' [nbrk' [ncnt' [A [B C]]]]]].
  rewrite A. exists ts'; exists tk'; exists nbrk'; exists ncnt'; auto.
  intro. rewrite H.
  eapply transl_find_label; eauto. econstructor; eauto. 
(* break *)
  auto.
(* continue *)
  auto.
(* return *)
  simpl in TR. destruct o; monadInv TR. auto. auto. 
(* switch *)
  eapply transl_find_label_ls with (k := Clight.Kswitch k); eauto. econstructor; eauto. 
(* label *)
  destruct (ident_eq lbl l). 
  exists x; exists tk; exists nbrk; exists ncnt; auto.
  eapply transl_find_label; eauto.
(* goto *)
  auto.

  intro ls; case ls; intros; monadInv TR; simpl.
(* default *)
  eapply transl_find_label; eauto.
(* case *)
  exploit (transl_find_label s j nbrk ncnt (Clight.Kseq (seq_of_labeled_statement l) k)); eauto. 
  econstructor; eauto. apply transl_lbl_stmt_2; eauto.
  destruct (Clight.find_label lbl s (Clight.Kseq (seq_of_labeled_statement l) k)) as [[s' k'] | ].
  intros [ts' [tk' [nbrk' [ncnt' [A [B C]]]]]].
  rewrite A. exists ts'; exists tk'; exists nbrk'; exists ncnt'; auto.
  intro. rewrite H.
  eapply transl_find_label_ls; eauto.
Qed.

End FIND_LABEL.

(** Properties of call continuations *)

Lemma match_cont_call_cont:
  forall j tyret' nbrk' ncnt' tyret nbrk ncnt k tk,
  match_cont j tyret nbrk ncnt k tk ->
  match_cont j tyret' nbrk' ncnt' (Clight.call_cont k) (call_cont tk).
Proof.
  induction 1; simpl; auto.
  constructor.
  econstructor; eauto. 
Qed.

Lemma match_cont_is_call_cont:
  forall j tyret nbrk ncnt k tk tyret' nbrk' ncnt',
  match_cont j tyret nbrk ncnt k tk ->
  Clight.is_call_cont k ->
  match_cont j tyret' nbrk' ncnt' k tk /\ is_call_cont tk.
Proof.
  intros. inv H; simpl in H0; try contradiction; simpl.
  split; auto; constructor.
  split; auto; econstructor; eauto.
Qed.

Lemma varinfo_preserved:
  forall b, (exists gv : globvar type, Genv.find_var_info ge b = Some gv) <->
            (exists gv : globvar unit, Genv.find_var_info tge b = Some gv).
Proof. intros.
  split; intros; destruct H.
    destruct (var_info_translated _ _ H). exists x0; apply H0.
    destruct (var_info_rev_translated _ _ H). exists x0; apply H0.
Qed.

Lemma GDE_lemma: genvs_domain_eq ge tge.
Proof.
    unfold genvs_domain_eq, genv2blocks.
    simpl; split; intros. 
     split; intros; destruct H as [id Hid].
       rewrite <- symbols_preserved in Hid.
       exists id; trivial.
     rewrite symbols_preserved in Hid.
       exists id; trivial.
    rewrite varinfo_preserved. intuition.
Qed.

(*From SimplLocals*)
Lemma assign_loc_inject:
  forall f ty m loc ofs v m' tm loc' ofs' v',
  assign_loc ty m loc ofs v m' ->
  val_inject f (Vptr loc ofs) (Vptr loc' ofs') ->
  val_inject f v v' ->
  Mem.inject f m tm ->
  exists tm',
     assign_loc ty tm loc' ofs' v' tm'
  /\ Mem.inject f m' tm'
  /\ (forall b chunk v,
      f b = None -> Mem.load chunk m b 0 = Some v -> Mem.load chunk m' b 0 = Some v).
Proof.
  intros. inv H.
  (* by value *)
  exploit Mem.storev_mapped_inject; eauto. intros [tm' [A B]].
  exists tm'; split. eapply assign_loc_value; eauto. 
  split. auto.
  intros. rewrite <- H5. eapply Mem.load_store_other; eauto.
  left. inv H0. congruence.
  (* by copy *)
  inv H0. inv H1.
  rename b' into bsrc. rename ofs'0 into osrc. 
  rename loc into bdst. rename ofs into odst.
  rename loc' into bdst'. rename b2 into bsrc'.
  exploit Mem.loadbytes_length; eauto. intros LEN.
  assert (SZPOS: sizeof ty > 0) by apply sizeof_pos.
  assert (RPSRC: Mem.range_perm m bsrc (Int.unsigned osrc) (Int.unsigned osrc + sizeof ty) Cur Nonempty).
    eapply Mem.range_perm_implies. eapply Mem.loadbytes_range_perm; eauto. auto with mem.
  assert (RPDST: Mem.range_perm m bdst (Int.unsigned odst) (Int.unsigned odst + sizeof ty) Cur Nonempty).
    replace (sizeof ty) with (Z_of_nat (length bytes)).
    eapply Mem.range_perm_implies. eapply Mem.storebytes_range_perm; eauto. auto with mem.
    rewrite LEN. apply nat_of_Z_eq. omega.
  assert (PSRC: Mem.perm m bsrc (Int.unsigned osrc) Cur Nonempty).
    apply RPSRC. omega.
  assert (PDST: Mem.perm m bdst (Int.unsigned odst) Cur Nonempty).
    apply RPDST. omega.
  exploit Mem.address_inject.  eauto. eexact PSRC. eauto. intros EQ1.
  exploit Mem.address_inject.  eauto. eexact PDST. eauto. intros EQ2.
  exploit Mem.loadbytes_inject; eauto. intros [bytes2 [A B]].
  exploit Mem.storebytes_mapped_inject; eauto. intros [tm' [C D]].
  exists tm'. 
  split. eapply assign_loc_copy; try rewrite EQ1; try rewrite EQ2; eauto. 
  eapply Mem.aligned_area_inject with (m := m); eauto. apply alignof_blockcopy_1248.
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.
  eapply Mem.aligned_area_inject with (m := m); eauto. apply alignof_blockcopy_1248.
  eapply Zdivide_trans. apply alignof_blockcopy_divides. apply sizeof_alignof_compat.
  eapply Mem.disjoint_or_equal_inject with (m := m); eauto.
  apply Mem.range_perm_max with Cur; auto.
  apply Mem.range_perm_max with Cur; auto.
  split. auto.
  intros. rewrite <- H0. eapply Mem.load_storebytes_other; eauto. 
  left. congruence.
Qed.

Lemma assign_loc_unique: forall t m b z v m1 m2
  (AL1: assign_loc t m b z v m1)
  (AL2: assign_loc t m b z v m2), m1=m2.
Proof. intros.
  inv AL1; inv AL2.
  rewrite H1 in H; inv H. rewrite H2 in H0; inv H0; trivial.
  rewrite H1 in H; inv H. 
  rewrite H5 in H; inv H.
  rewrite H7 in H; inv H.
    destruct (loadbytes_D _ _ _ _ _ H3).
    destruct (loadbytes_D _ _ _ _ _ H11).
    rewrite <- H5 in H12. clear H5. subst.
    rewrite H4 in H13; inv H13; trivial.
Qed.   

Definition MATCH (d:CL_core) mu c1 m1 c2 m2:Prop :=
  match_states (restrict (as_inj mu) (vis mu)) c1 m1 c2 m2 /\
  REACH_closed m1 (vis mu) /\
  meminj_preserves_globals ge (as_inj mu) /\
  globalfunction_ptr_inject (as_inj mu) /\
  (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true) /\
  sm_valid mu m1 m2 /\ SM_wd mu /\ Mem.inject (as_inj mu) m1 m2.

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
  destruct MC as [MS [RC [PG [GF [Glob [SMV [WD INJ]]]]]]].
assert (WDR: SM_wd (restrict_sm mu X)).
   apply restrict_sm_WD; assumption.
split.
  rewrite vis_restrict_sm.
  rewrite restrict_sm_all.
  rewrite restrict_nest; intuition.
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

Lemma MATCH_initial: forall v vals1 c1 m1 j vals2 m2 (DomS DomT : block -> bool)
      (FE : Clight.function -> list val -> mem -> Clight.env -> Clight.temp_env -> mem -> Prop)
      (FE_FWD : forall f vargs m e lenv m', FE f vargs m e lenv m' ->
                mem_forward m m')
      (FE_UNCH : forall f vargs m e lenv m', FE f vargs m e lenv m' ->
          Mem.unchanged_on
            (fun (b : block) (z : Z) => EmptyEffect b z = false) m m')
      (Ini: initial_core (clight_eff_sem hf FE FE_FWD FE_UNCH) ge v vals1 = Some c1)
      (Inj: Mem.inject j m1 m2)
      (VInj: Forall2 (val_inject j) vals1 vals2)
      (PG:meminj_preserves_globals ge j)
      (R : list_norepet (map fst (prog_defs prog)))
      (J: forall b1 b2 delta, j b1 = Some (b2, delta) -> 
            (DomS b1 = true /\ DomT b2 = true))
      (RCH: forall b, REACH m2 
          (fun b' : block => isGlobalBlock tge b' || getBlocks vals2 b') b = true ->
          DomT b = true)
      (InitMem : exists m0 : mem, Genv.init_mem prog = Some m0 
               /\ Ple (Mem.nextblock m0) (Mem.nextblock m1) 
               /\ Ple (Mem.nextblock m0) (Mem.nextblock m2))   
      (GDE: genvs_domain_eq ge tge)
      (HDomS: forall b : block, DomS b = true -> Mem.valid_block m1 b)
      (HDomT: forall b : block, DomT b = true -> Mem.valid_block m2 b),
exists c2,
  initial_core (csharpmin_eff_sem hf) tge v vals2 = Some c2 /\
  MATCH c1
    (initial_SM DomS DomT
       (REACH m1 (fun b : block => isGlobalBlock ge b || getBlocks vals1 b))
       (REACH m2 (fun b : block => isGlobalBlock tge b || getBlocks vals2 b))
       j) c1 m1 c2 m2.
Proof. 
intros.
  simpl in Ini.
  unfold  CL_initial_core in Ini. unfold ge in *. unfold tge in *.
  destruct v; inv Ini.
  remember (Int.eq_dec i Int.zero) as z; destruct z; inv H0. clear Heqz.
  remember (Genv.find_funct_ptr (Genv.globalenv prog) b) as zz; destruct zz.
    apply eq_sym in Heqzz.
  destruct f; try discriminate.
  remember (type_of_fundef (Internal f)) as tf.
  destruct tf; try solve[inv H1].
  case_eq (val_casted.val_casted_list_func vals1 t).
  2: solve[intros cast; rewrite cast in H1; inv H1].
  intros cast. case_eq (val_casted.vals_defined vals1).
  2: solve[intros def; rewrite cast, def in H1; simpl in H1;
           rewrite <-andb_assoc, andb_comm in H1; inv H1].
  intros def; rewrite cast,def in H1. simpl in H1. 
  rewrite andb_comm in H1; simpl in H1.
  case_eq (val_casted.tys_nonvoid t). 
  2: solve[intros nvoid; rewrite nvoid, andb_comm in H1; inv H1].
  intros nvoid; rewrite nvoid in H1. inv H1.
  revert H0; case_eq 
         (zlt (match match Zlength vals1 with 0 => 0
                      | Z.pos y' => Z.pos y'~0 | Z.neg y' => Z.neg y'~0
                     end
               with 0 => 0
                 | Z.pos y' => Z.pos y'~0~0 | Z.neg y' => Z.neg y'~0~0
               end) Int.max_unsigned); simpl.
  2: solve[inversion 2]. intros l _. inversion 1; subst.
  exploit function_ptr_translated; eauto. intros [tf' [FIND TR]].
  exists (CSharpMin_Callstate tf' vals2 Kstop).
  split. simpl. 
  subst. inv Heqzz. unfold tge in FIND. inv FIND. rewrite H2.
  unfold CSharpMin_initial_core. 
  case_eq (Int.eq_dec Int.zero Int.zero). intros ? e.
  assert (Hlen: Zlength vals2 = Zlength vals1).
  { apply forall_inject_val_list_inject in VInj. clear - VInj. 
    induction VInj; auto. rewrite !Zlength_cons, IHVInj; auto. }

  assert (val_casted.val_has_type_list_func vals2
           (sig_args (funsig tf'))=true) as ->.
  { eapply val_casted.val_list_inject_hastype; eauto.
    eapply forall_inject_val_list_inject; eauto.
    eapply transl_fundef_sig2 in TR; eauto.
    rewrite TR. simpl. 
    apply val_casted.val_casted_has_type_list; auto. }

  assert (val_casted.vals_defined vals2=true) as ->.
  { eapply val_casted.val_list_inject_defined.
    eapply forall_inject_val_list_inject; eauto.
    destruct (val_casted.vals_defined vals1); auto. }
  monadInv TR. rename x into tf'. 
  rewrite Hlen. simpl.
  case_eq 
    (zlt (match match Zlength vals1 with 0%Z => 0%Z
                      | Z.pos y' => Z.pos y'~0 | Z.neg y' => Z.neg y'~0
                     end
               with 0%Z => 0%Z
                 | Z.pos y' => Z.pos y'~0~0 | Z.neg y' => Z.neg y'~0~0
               end) Int.max_unsigned).
  simpl; auto. simpl. inversion 1. omega.
  intros CONTRA. solve[elimtype False; auto].

  assert (H : exists targs tres, type_of_fundef (Internal f) = Tfunction targs tres).
  { destruct f; simpl. eexists; eexists. reflexivity. }
  destruct H as [targs [tres Tfun]].
  destruct (core_initial_wd ge tge _ _ _ _ _ _ _  Inj
     VInj J RCH PG GDE HDomS HDomT _ (eq_refl _))
    as [AA [BB [CC [DD [EE [FF GG]]]]]].
  split.
    eapply match_callstate; try eassumption.
      constructor.
      constructor.
    rewrite initial_SM_as_inj.
      unfold vis, initial_SM; simpl.
      apply forall_inject_val_list_inject.
      eapply restrict_forall_vals_inject; try eassumption.
        intros. apply REACH_nil. rewrite H; intuition.
  intuition.
    rewrite match_genv_meminj_preserves_extern_iff_all.
      assumption.
      apply BB.
      apply EE.
    rewrite initial_SM_as_inj.
      red; intros. specialize (Genv.find_funct_ptr_not_fresh prog). intros.
         destruct InitMem as [m0 [InitMem [? ?]]].
         specialize (H1 _ _ _ InitMem H). 
         destruct (valid_init_is_global _ R _ InitMem _ H1) as [id Hid]. 
           destruct PG as [PGa [PGb PGc]]. split. eapply PGa; eassumption.
         unfold isGlobalBlock. 
          apply orb_true_iff. left. apply genv2blocksBool_char1.
            simpl. exists id; eassumption.
    rewrite initial_SM_as_inj; assumption.
  inv H1.
Qed.

Lemma MATCH_afterExternal: forall
      (FE : Clight.function -> list val -> mem -> 
            Clight.env -> Clight.temp_env -> mem -> Prop)
      (FE_FWD : forall f vargs m e lenv m',
         FE f vargs m e lenv m' -> mem_forward m m')
      (FE_UNCH : forall f vargs m e lenv m',
         FE f vargs m e lenv m' -> 
         Mem.unchanged_on
            (fun (b : block) (z : Z) => EmptyEffect b z = false) m m')
      (GDE : genvs_domain_eq ge tge)
      mu st1 st2 m1 e vals1 m2 ef_sig vals2 e' ef_sig'
      (MemInjMu : Mem.inject (as_inj mu) m1 m2)
      (MatchMu: MATCH st1 mu st1 m1 st2 m2)
      (AtExtSrc : at_external (clight_eff_sem hf FE FE_FWD FE_UNCH) st1 = Some (e, ef_sig, vals1))
      (AtExtTgt : at_external (csharpmin_eff_sem hf) st2 = Some (e', ef_sig', vals2))
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
  exists (st1' : CL_core) (st2' : CSharpMin_core),
  after_external (clight_eff_sem hf FE FE_FWD FE_UNCH) (Some ret1) st1 =Some st1' /\
  after_external (csharpmin_eff_sem hf) (Some ret2) st2 = Some st2' /\
  MATCH st1' mu' st1' m1' st2' m2'.
Proof. intros.
simpl.
 destruct MatchMu as [MC [RC [PG [GF [Glob [VAL [WDmu INJ]]]]]]].
 simpl in *. inv MC; simpl in *; inv AtExtSrc.
 destruct fd; inv H0. simpl in TY. inv TY.
 destruct tfd; inv AtExtTgt.
 destruct (observableEF_dec hf e0); inv H1.
 destruct (observableEF_dec hf e1); inv H0.
 simpl in *.
 remember (list_typ_eq (sig_args (ef_sig e)) (typlist_of_typelist targs) &&
           opt_typ_eq (sig_res (ef_sig e)) (opttyp_of_type tres)) as dd.
 destruct dd; inv TR. clear o0; rename o into OBS.
 eexists. eexists.
    split. reflexivity.
    split. reflexivity.
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
  specialize (IHL _ H1); clear H1.
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
        apply (H VB) in H2.
        rewrite (H0 H2) in H4. clear H H0.
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
     intros. specialize (Glob _ H).
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
  unfold vis in *.
  rewrite replace_externs_frgnBlocksSrc, replace_externs_locBlocksSrc in *.
  econstructor; try eassumption.
    eapply match_cont_inject_incr; try eassumption.
      rewrite (*restrict_sm_all, *)replace_externs_as_inj.
      clear RRC RR1 RC' PHnu' INCvisNu' UnchLOOR UnchPrivSrc.
      destruct INC. rewrite replace_locals_extern in H.
        rewrite replace_locals_frgnBlocksTgt, replace_locals_frgnBlocksSrc,
                replace_locals_pubBlocksTgt, replace_locals_pubBlocksSrc,
                replace_locals_locBlocksTgt, replace_locals_locBlocksSrc,
                replace_locals_extBlocksTgt, replace_locals_extBlocksSrc,
                replace_locals_local in H0.
        destruct H0 as [? [? [? [? [? [? [? [? ?]]]]]]]].
        red; intros. destruct (restrictD_Some _ _ _ _ _ H9); clear H9.
          apply restrictI_Some.
            apply joinI.
            destruct (joinD_Some _ _ _ _ _ H10).
              apply H in H9. left; trivial.
            destruct H9. right. rewrite H0 in H12.
              split; trivial.
              destruct (disjoint_extern_local _ WDnu' b); trivial. congruence.
          rewrite H3, H7 in H11.
            remember (locBlocksSrc nu' b) as d.
            destruct d; trivial; simpl in *.
            apply andb_true_iff.
            split. unfold DomSrc. rewrite (frgnBlocksSrc_extBlocksSrc _ WDnu' _ H11). intuition.
               apply REACH_nil. unfold exportedSrc. 
                 apply frgnSrc_shared in H11; trivial. rewrite H11; intuition.
      rewrite replace_externs_as_inj. (*rewrite replace_externs_frgnBlocksSrc, replace_externs_locBlocksSrc. *)
       eapply restrict_val_inject; try eassumption.
       intros.
        destruct (getBlocks_inject (as_inj nu') (ret1::nil) (ret2::nil))
           with (b:=b) as [bb [dd [JJ' GBbb]]]; try eassumption.
          constructor. assumption. constructor.
        remember (locBlocksSrc nu' b) as d.
        destruct d; simpl; trivial. apply andb_true_iff.
        split. eapply as_inj_DomRng; eassumption.
        apply REACH_nil. unfold exportedSrc.
           rewrite H. trivial.
unfold vis.
rewrite replace_externs_locBlocksSrc, replace_externs_frgnBlocksSrc,
        replace_externs_as_inj.
destruct (eff_after_check2 _ _ _ _ _ MemInjNu' RValInjNu' 
      _ (eq_refl _) _ (eq_refl _) _ (eq_refl _) WDnu' SMvalNu').
intuition.
(*last goal: globalfunction_ptr_inject *)
  red; intros. destruct (GF _ _ H1). split; trivial.
  eapply extern_incr_as_inj; try eassumption.
  rewrite replace_locals_as_inj. assumption.
Qed.

Lemma transl_expr_correctMu: forall e le m a v te tle tm mu 
       (EVAL: Clight.eval_expr ge e le m a v)
       (MENV : match_env (restrict (as_inj mu) (vis mu)) e te)
       (TENV : match_tempenv (restrict (as_inj mu) (vis mu)) le tle)
       (INJ : Mem.inject (as_inj mu) m tm)
       (PG : meminj_preserves_globals ge (as_inj mu))
       (RC: REACH_closed m (vis mu))
       (GLOB: forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true),
       forall ta, transl_expr a = OK ta ->
       exists tv, val_inject (restrict (as_inj mu) (vis mu)) v tv /\ 
            eval_expr tge te tle tm ta tv.
Proof. intros.
         assert (MinjR:  Mem.inject (restrict (as_inj mu) (vis mu)) m tm).
           eapply inject_restrict; eassumption.
         assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
           assert (PGR': meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
              eapply restrict_sm_preserves_globals; try eassumption.
              unfold vis. intuition. 
           rewrite restrict_sm_all in PGR'. assumption.  
      eapply (transl_expr_correct _ _ _ _ _ _ _ MENV TENV MinjR PGR); eassumption.
Qed.

Lemma transl_arglist_correctMu:
  forall e le m al tyl vl mu te tle tm 
        (EVAL:Clight.eval_exprlist ge e le m al tyl vl)
       (MENV : match_env (restrict (as_inj mu) (vis mu)) e te)
       (TENV : match_tempenv (restrict (as_inj mu) (vis mu)) le tle)
       (INJ : Mem.inject (as_inj mu) m tm)
       (PG : meminj_preserves_globals ge (as_inj mu))
       (RC: REACH_closed m (vis mu))
       (GLOB: forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true),
  forall tal, transl_arglist al tyl = OK tal ->
  exists tvl, val_list_inject (restrict (as_inj mu) (vis mu)) vl tvl /\
  Csharpminor.eval_exprlist tge te tle tm tal tvl.
Proof. intros.
         assert (MinjR:  Mem.inject (restrict (as_inj mu) (vis mu)) m tm).
           eapply inject_restrict; eassumption.
         assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
           assert (PGR': meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
              eapply restrict_sm_preserves_globals; try eassumption.
              unfold vis. intuition. 
           rewrite restrict_sm_all in PGR'. assumption.  
      eapply transl_arglist_correct; try eassumption.
Qed. 

Lemma blocks_of_bindingD: forall l b lo hi 
      (I: In (b,lo,hi) (map block_of_binding l)),
      lo=0 /\ exists x, In (x,(b,hi)) l.
Proof. intros l.
  induction l; simpl; intros. contradiction.
  destruct I. 
    destruct a as [? [? ?]]. simpl in H. inv H.
    split; trivial. exists i; left; trivial.
  destruct (IHl _ _ _ H) as [HH [x Hx]].
  split; trivial. exists x; right; trivial.
Qed.

Lemma blocks_of_envD: forall te b lo hi 
       (I:In (b, lo, hi) (blocks_of_env te)),
  lo = 0 /\ exists x, te!x=Some(b,hi).
Proof. intros.
  destruct (blocks_of_bindingD _ _ _ _ I) as [HH [x Hx]].
  split; trivial.
  exists x. eapply PTree.elements_complete. apply Hx.
Qed.


Lemma MATCH_corediagram: forall
  (st1 : CL_core) (m1 : mem) (st1' : CL_core) (m1' : mem)
(*  (CS: corestep (clight_eff_sem FE FE_FWD FE_UNCH) ge st1 m1 st1' m1')*)
  (CS: corestep (CL_eff_sem2 hf) ge st1 m1 st1' m1')
  (st2 : CSharpMin_core) (mu : SM_Injection) (m2 : mem)
  (MC: MATCH st1 mu st1 m1 st2 m2),
exists (st2' : CSharpMin_core) (m2' : mem) (mu' : SM_Injection),
  
  corestep_plus (csharpmin_eff_sem hf) tge st2 m2 st2' m2' /\
  intern_incr mu mu' /\
  sm_inject_separated mu mu' m1 m2 /\
  sm_locally_allocated mu mu' m1 m2 m1' m2' /\
  MATCH st1' mu' st1' m1' st2' m2' /\
  SM_wd mu' /\ sm_valid mu' m1' m2'.
Proof.
  intros. 
  assert (SymbPres := symbols_preserved).
  inv CS; simpl in *.

{ (*corestep_assign*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      try (monadInv TR).
      destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      assert (SAME: ts' = ts /\ tk' = tk).
        inversion MTR. auto.   
        subst ts. unfold make_store, make_memcpy in EQ3.
        destruct (access_mode (typeof a1)); congruence.
      destruct SAME; subst ts' tk'.
      assert (MinjR:  Mem.inject (restrict (as_inj mu) (vis mu)) m1 m2).
           eapply inject_restrict; eassumption.
      assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
           rewrite <- restrict_sm_all. 
           eapply restrict_sm_preserves_globals; try eassumption.
           unfold vis. intuition.    
      destruct (transl_lvalue_correct _ _ _ _ _ _ _ MENV TENV MinjR PGR _ _ _ H _ EQ)
            as [vv [Hvv1 EvalX]]; inv Hvv1. 
      destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV MinjR PGR _ _ H0 _ EQ1)
            as [uu [VinjU EvalX0]].
      destruct (sem_cast_inject _ _ _ _ _ _ H1 VinjU) as [? [? ?]].
         assert (EVAL:= make_cast_correct _ _ _ _ _ _ _ _ _ _ EQ0 EvalX0 H3).
      (*destruct (assign_loc_inject _ _ _ _ _ _ _ H2 _ _ H4 _ _ H5 _ INJ)
            as [m2' [AL2 MINJ']].*)
      exploit assign_loc_inject. eapply H2.
          econstructor. eapply restrictD_Some. eapply H5. reflexivity.
          eapply val_inject_incr; try eapply H4. apply restrict_incr.
          eassumption.
      intros [m2' [AL2 [INJ' LD]]].
      eexists. eexists. exists mu.
      split.          
         apply corestep_plus_one.
         eapply make_store_correct. eapply EQ3. eassumption. eassumption. eassumption.
      assert (SMV': sm_valid mu m1' m2').
        inv H2. 
        (*by_value*)
        inv AL2.
          split; intros.   
            eapply storev_valid_block_1; try eassumption.
            eapply SMV; assumption.
          eapply storev_valid_block_1; try eassumption.
            eapply SMV; assumption.
        rewrite H2 in H6. discriminate.
        (*by_chunk*)
        inv AL2.
          rewrite H2 in H6. discriminate.
        split; intros.   
            eapply Mem.storebytes_valid_block_1; try eassumption.
            eapply SMV; assumption.
          eapply Mem.storebytes_valid_block_1; try eassumption.
            eapply SMV; assumption.
      intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
        repeat split; extensionality b; 
        try rewrite (assign_loc_freshloc _ _ _ _ _ _ AL2);
        try rewrite (assign_loc_freshloc _ _ _ _ _ _ H2); intuition.
      econstructor. 
        eapply match_states_skip; eauto.
        intuition.
        (*REACH_closed*)
          inv H2.
          (*by_value*)
             inv H7. 
             eapply REACH_Store; try eassumption.
             apply (restrictD_Some _ _ _ _ _ H5).
             intros b' Hb'. rewrite getBlocksD, getBlocksD_nil in Hb'.
               destruct v; inv Hb'. rewrite orb_false_r in H7.
               rewrite H7. simpl.
              assert (b=b').
                remember (eq_block b b') as d.
                destruct d; intuition.
              subst. inv H4. apply (restrictD_Some _ _ _ _ _ H10).
          (*by_copy*)
             eapply REACH_Storebytes; try eassumption.
             apply (restrictD_Some _ _ _ _ _ H5).
             intros bb off n Hbb. inv H4.
             destruct (Mem.loadbytes_inject _ _ _ _ _ _ _ _ _ MinjR H10 H13)
                as [bytes2 [LoadBytes2 MapBytes]].
             clear - Hbb MapBytes.
               induction MapBytes; inv Hbb.
               inv H. apply (restrictD_Some _ _ _ _ _ H4).
               apply (IHMapBytes H0).
        (*assert (VI: val_inject (as_inj mu) v x2).
           eapply val_inject_incr; try eassumption.
           eapply restrict_incr.
        destruct (restrictD_Some _ _ _ _ _ H5). 
        destruct (assign_loc_inject _ _ _ _ _ _ H2 _ _ VI _ _ H6 _ INJ)
           as [m2'' [AL2' INJ'']]. 
        rewrite (assign_loc_unique _ _ _ _ _ _ _ AL2 AL2'). assumption.*) }

{ (*clight_corestep_set*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      try (monadInv TR).
      inv MTR. destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      exploit transl_expr_correctMu; try eassumption.
        intros [uu [VinjU EvalX0]].
      eexists; eexists. exists mu.
      split. apply corestep_plus_one.
               econstructor. eassumption.
      intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
        eapply match_tempenv_set; eassumption.
      intuition. }

{ (*clight_corestep_call*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      revert TR. simpl. case_eq (classify_fun (typeof a)); try congruence.
      intros targs tres CF TR. monadInv TR. inv MTR. 
      exploit functions_translated; eauto. intros [tfd [FIND TFD]].
      rewrite H in CF. simpl in CF. inv CF.
      destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      exploit transl_expr_correctMu; try eassumption.
        intros [tvf [VinjE EvalE]].
      exploit transl_arglist_correctMu; try eassumption.
        intros [tvl [Vargs EvalArgs]].
      inv VinjE; inv FIND.
      destruct (Int.eq_dec ofs1 Int.zero); try inv H6.
      destruct (GF _ _ H2).
      destruct (restrictD_Some _ _ _ _ _ H4).
      rewrite H8 in H5; inv H5. 
      eexists; eexists. exists mu.
      split. apply corestep_plus_one.
               econstructor; try eassumption.
               eapply transl_fundef_sig1; eauto.
             rewrite H3. auto.
      intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto.    
          econstructor.
      intuition. }

{ (* builtin *)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      monadInv TR. inv MTR.
    destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
    assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m1 m2).
      eapply inject_restrict; eassumption.
    assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
      rewrite <- restrict_sm_all. 
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis. intuition. 
    exploit transl_arglist_correct; try eassumption.
    intros [tvargs [EVAL2 VINJ2]].
    exploit (inlineable_extern_inject _ _ GDE_lemma); 
     try eapply H0; try  eassumption. 
    intros [mu' [vres' [tm' [EC [VINJ [MINJ' [UNMAPPED [OUTOFREACH 
           [INCR [SEPARATED [LOCALLOC [WD' [VAL' RC']]]]]]]]]]]]].
    eexists; eexists; eexists mu'.
      split. apply corestep_plus_one.
             econstructor; eassumption. 
    intuition.
    split. assert (INC:= intern_incr_restrict _ _ WD' INCR).
           econstructor; eauto.
           Focus 5. eapply match_cont_inject_incr; eassumption.
           reflexivity. constructor.
           eapply match_env_inject_incr; eassumption.
           assert (TENV':= match_tempenv_inject_incr _ _ _ TENV _ INC).
           destruct optid; trivial; simpl.
           eapply match_tempenv_set; eassumption.
         intuition.
         eapply meminj_preserves_incr_sep. eapply PG. eassumption. 
             apply intern_incr_as_inj; trivial.
             apply sm_inject_separated_mem; eassumption.
         red. intros b fbb Hb. destruct (GF _ _ Hb).
           split; trivial.
           eapply intern_incr_as_inj; eassumption.
         assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INCR.
           rewrite <- FRG. apply Glob; assumption. }

{ (* seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *. 
  monadInv TR. inv MTR.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           constructor.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto.  
      intuition. }

{ (* skip seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           apply csharpmin_corestep_skip_seq.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
      intuition. }

{ (* continue seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           econstructor; eauto. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* break seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           econstructor; eauto. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* ifthenelse *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  exploit make_boolean_inject; eauto.
      eapply inject_restrict; eassumption.
      assert (PGR': meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
              eapply restrict_sm_preserves_globals; try eassumption.
              unfold vis. intuition. 
           rewrite restrict_sm_all in PGR'. assumption.
  intros [tv [Etv Btv]].  
  exploit transl_expr_correctMu; try eassumption.
        intros [tv1 [V1inj EvalV1]].
  eexists; eexists. exists mu.
  split. apply corestep_plus_one. 
         apply csharpmin_corestep_ifthenelse with (v := tv) (b := b); auto.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality bb; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        destruct b; econstructor; eauto; constructor.
      intuition. }

{ (* loop *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. 
  exists (CSharpMin_State tf x
     (Kblock (Kseq x0 (Kseq (Sloop (Sseq (Sblock x) x0)) (Kblock tk)))) te tle).
  eexists. exists mu.
  split. 
    eapply corestep_star_plus_trans.
      eapply match_transl_corestep; eauto. 
    eapply corestep_plus_star_trans.
      eapply corestep_plus_one.
        econstructor.
    eapply corestep_star_trans.
      eapply corestep_star_one.
        econstructor.
      eapply corestep_star_one.
        econstructor.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; try eassumption.
          econstructor.
          econstructor; eassumption. 
      intuition. }

{ (* skip-or-continue loop *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  assert ((ts' = Sskip \/ ts' = Sexit ncnt) /\ tk' = tk).
    destruct H; subst x; monadInv TR; inv MTR; auto.
  destruct H0. inv MK.
  eexists; eexists. exists mu.
  split. eapply corestep_plus_star_trans.
          destruct H0; subst ts'.
           Focus 2. eapply corestep_plus_one. econstructor.
           eapply corestep_plus_one. econstructor.
         eapply corestep_star_one.
          econstructor. 
  clear H0 H.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* break loop1 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eapply corestep_plus_star_trans.
           eapply corestep_plus_one. econstructor.
         eapply corestep_star_trans.
           eapply corestep_star_one.
             econstructor. 
         eapply corestep_star_trans.
           eapply corestep_star_one.
             econstructor. 
           eapply corestep_star_one.
             econstructor. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* skip loop2 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one. constructor.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.    
          simpl. rewrite H5; simpl. rewrite H7; simpl. eauto. 
          constructor. 
      intuition. }

{ (* break loop2 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eapply corestep_plus_trans.
           eapply corestep_plus_one. constructor.
           eapply corestep_plus_one. constructor. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* return none *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]]. 
  exploit match_env_free_blocks_parallel_inject; eauto.
      eapply inject_restrict; eassumption.
    intros [m2' [FL2 Inj']].   
  eexists; eexists. exists mu.
  split. apply corestep_plus_one. constructor. eassumption.
  assert (SMV': sm_valid mu m1' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H); intuition.
      econstructor.
        econstructor; eauto.
          eapply match_cont_call_cont. eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* return some *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m1 m2).
      eapply inject_restrict; eassumption.
  assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
     rewrite <- restrict_sm_all. 
     eapply restrict_sm_preserves_globals; try eassumption.
     unfold vis. intuition. 
  exploit match_env_free_blocks_parallel_inject; eauto.
    intros [m2' [FL2 Inj']].
  destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV InjR 
            PGR _ _ H _ EQ) as [tv [VInj EvalA]].
  destruct (sem_cast_inject _ _ _ _ _ _ H0 VInj) as [tv' [SemCast' VInj']].
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           constructor; try eassumption.
           eapply make_cast_correct; eauto.
  assert (SMV': sm_valid mu m1' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H1); intuition.
      econstructor.
        econstructor; eauto.
          eapply match_cont_call_cont. eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* skip call *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  exploit match_cont_is_call_cont; eauto. intros [A B].
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m1 m2).
      eapply inject_restrict; eassumption.
  destruct (match_env_free_blocks_parallel_inject _ _ _ _ _ _ MENV InjR H0) as [m2' [FL2 Inj']].
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           apply csharpmin_corestep_skip_call. auto.
           eassumption.
  assert (SMV': sm_valid mu m1' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H0); intuition.
      econstructor.
        econstructor; eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m1' m2).
      eapply inject_restrict; eassumption.
  assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
     rewrite <- restrict_sm_all. 
     eapply restrict_sm_preserves_globals; try eassumption.
     unfold vis. intuition. 
  destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV InjR 
            PGR _ _ H _ EQ) as [tv [VInj EvalA]].
  inv VInj.

  eexists; eexists. exists mu.
  split. eapply corestep_star_plus_trans.
           eapply match_transl_corestep; eauto.
         eapply corestep_plus_one.
           econstructor. eauto. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; try eassumption.
          apply transl_lbl_stmt_2. apply transl_lbl_stmt_1. eauto.  
          constructor.
          econstructor. eauto.
      intuition. }

{ (* skip or break switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  assert ((ts' = Sskip \/ ts' = Sexit nbrk) /\ tk' = tk).
    destruct H; subst x; monadInv TR; inv MTR; auto.
  destruct H0. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           destruct H0; subst ts'.
            2: constructor. constructor.
  clear H0 H. 
  intuition.
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* continue switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           constructor.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. simpl. reflexivity. constructor.
      intuition. }

{ (* label *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. 
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           constructor. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. constructor.
      intuition. }

{ (* goto *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  generalize TRF. unfold transl_function. intro TRF'. monadInv TRF'.
  exploit (transl_find_label lbl). eexact EQ.
  eapply match_cont_call_cont. eauto.
  rewrite H. 
  intros [ts' [tk'' [nbrk' [ncnt' [A [B C]]]]]].
  eexists; eexists. exists mu.
  split. apply corestep_plus_one.
           constructor. simpl. eexact A. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. constructor.
      intuition. }

{ (* internal function *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  inv H. monadInv TR. monadInv EQ.
  exploit match_cont_is_call_cont; eauto. intros [A B].
  exploit match_env_alloc_variables; try eassumption. 
    apply match_env_empty.
  intros [te1 [m2' [mu' [AVars2 [MENV' [INJ' [INC'
         [SEP' [LAC' [WD' [VAL' RC']]]]]]]]]]].
  specialize (create_undef_temps_match_inject 
         (Clight.fn_temps f) (restrict (as_inj mu') (vis mu'))); intros. 
  destruct (bind_parameter_temps_match_inject
       _ _ _ _ H4 _ _ H args2)
     as [tle [BP TENV]].
     eapply val_list_inject_incr; try eassumption.
       eapply intern_incr_restrict; eassumption.
  eexists; exists m2'. exists mu'.
  split. apply corestep_plus_one.
           eapply csharpmin_corestep_internal_function.
         simpl. rewrite list_map_compose. simpl. assumption.
         simpl. auto.
         simpl. auto.
         simpl. eauto.
         simpl. eassumption.
  intuition.
    constructor.
      simpl. econstructor; try eassumption.
         unfold transl_function. rewrite EQ0; simpl. auto.         
         constructor.
         eapply match_cont_inject_incr; try eassumption.
           eapply intern_incr_restrict; eassumption.
    destruct (@intern_incr_meminj_preserves_globals_as_inj _ _ ge _ WD) with (mu' := mu').
        split; trivial. trivial. trivial.
    intuition.
       red; intros. destruct (GF _ _ H8). split; trivial.
           eapply intern_incr_as_inj; eassumption. }

{ (* returnstate *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  inv MK. 
  eexists; exists m2. exists mu.
  split. apply corestep_plus_one.
           constructor.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. simpl; reflexivity. 
           constructor.
        unfold set_opttemp. 
        destruct optid. 
          eapply match_tempenv_set; eassumption.
          simpl. assumption.
      intuition. }
Qed.

Lemma Match_effcore_diagram: forall
  (st1 : CL_core) (m1 : mem) (st1' : CL_core) (m1' : mem)
  (U1 : block -> Z -> bool)
  (EFFSTEP: effstep (CL_eff_sem2 hf) ge U1 st1 m1 st1' m1')
  (st2 : CSharpMin_core) (mu : SM_Injection) (m2 : mem)
  (UHyp: forall b z, U1 b z = true -> vis mu b = true) 
  (MC: MATCH st1 mu st1 m1 st2 m2),
exists (st2' : CSharpMin_core) (m2' : mem) (mu' : SM_Injection),
  (exists U2 : block -> Z -> bool,
     (effstep_plus (csharpmin_eff_sem hf) tge U2 st2 m2 st2' m2' /\
     (forall (b : block) (ofs : Z),
      U2 b ofs = true ->
      visTgt mu b = true /\
      (locBlocksTgt mu b = false ->
       exists (b1 : block) (delta1 : Z),
         foreign_of mu b1 = Some (b, delta1) /\
         U1 b1 (ofs - delta1) = true /\
         Mem.perm m1 b1 (ofs - delta1) Max Nonempty))))
  /\
  intern_incr mu mu' /\
  sm_inject_separated mu mu' m1 m2 /\
  sm_locally_allocated mu mu' m1 m2 m1' m2' /\
  MATCH st1' mu' st1' m1' st2' m2'.
Proof.
  intros. 
  assert (SymbPres := symbols_preserved).
  induction EFFSTEP; simpl in *.

{ (*corestep_assign*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      try (monadInv TR).
      destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      assert (SAME: ts' = ts /\ tk' = tk).
        inversion MTR. auto.   
        subst ts. unfold make_store, make_memcpy in EQ3.
        destruct (access_mode (typeof a1)); congruence.
      destruct SAME; subst ts' tk'.
      assert (MinjR:  Mem.inject (restrict (as_inj mu) (vis mu)) m m2).
           eapply inject_restrict; eassumption.
      assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
           rewrite <- restrict_sm_all. 
           eapply restrict_sm_preserves_globals; try eassumption.
           unfold vis. intuition.      
      destruct (transl_lvalue_correct _ _ _ _ _ _ _ MENV TENV MinjR PGR _ _ _ H _ EQ)
            as [vv [Hvv1 EvalX]]; inv Hvv1. 
      destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV MinjR PGR _ _ H0 _ EQ1)
            as [uu [VinjU EvalX0]].
      destruct (sem_cast_inject _ _ _ _ _ _ H1 VinjU) as [? [? ?]].
      assert (EVAL:= make_cast_correct _ _ _ _ _ _ _ _ _ _ EQ0 EvalX0 H3).

      exploit assign_loc_inject. 
        eassumption.
        econstructor. eapply restrictD_Some. eapply H5. reflexivity.
        eapply val_inject_incr; try eapply H4. apply restrict_incr.
        eassumption.
      intros [m2' [AL2 INJ']]. 
      exploit make_store_correct_StoreEffect. eassumption. eassumption. eassumption. eassumption.
      intros EffStep'.
      specialize (assign_loc_freshloc _ _ _ _ _ _ H2). intros Freshloc.
      specialize (assign_loc_forward _ _ _ _ _ _ H2). intros FWD.
      inv H2; rewrite H6 in EffStep'.
      (*by_value*)
        eexists. eexists. exists mu.
        split. eexists.
               split. apply effstep_plus_one. eassumption.
               intros.
               apply StoreEffectD in H2. destruct H2 as [i [VV Arith]].
                 inv VV.
               split. eapply visPropagateR; eassumption.
               exists loc, delta.
                   split. eapply restrict_vis_foreign; eassumption.
                   inv H7.
                   assert (WR:Mem.perm m loc (Int.unsigned ofs) Cur Writable).
                      eapply Mem.store_valid_access_3; try eassumption. 
                      specialize (size_chunk_pos chunk); intros. omega.
                   destruct (restrictD_Some _ _ _ _ _ H5) as [AI VIS]; clear H5.
                   rewrite (Mem.address_inject _ _ _ loc ofs b delta Writable INJ WR AI) in Arith.
                   rewrite encode_val_length in *.
                   split. unfold assign_loc_Effect. rewrite H6.
                          destruct (eq_block loc loc); simpl. 
                            clear e0. 
                               destruct (zle (Int.unsigned ofs) (ofs0 - delta)); simpl in *. 
                                 destruct (zlt (ofs0 - delta) (Int.unsigned ofs + Z.of_nat (size_chunk_nat chunk))); simpl; trivial.
                                 clear - Arith g H4. omega.
                                omega.
                            elim n; trivial.
                   rewrite <- size_chunk_conv in *.
                     eapply Mem.perm_implies. 
                     eapply Mem.perm_max.
                       eapply Mem.store_valid_access_3; try eassumption. omega. 
                       constructor. 
        intuition. 
        apply intern_incr_refl. 
        apply sm_inject_separated_same_sminj.
        apply sm_locally_allocatedChar.
          repeat split; extensionality b.
          rewrite Freshloc. intuition.
          rewrite (assign_loc_freshloc _ _ _ _ _ _ AL2). intuition.
          rewrite Freshloc. intuition.
          rewrite (assign_loc_freshloc _ _ _ _ _ _ AL2). intuition.
        econstructor.
          econstructor; eauto. reflexivity. constructor.
          destruct (restrictD_Some _ _ _ _ _ H5).
          intuition.
          clear AL2.
            inv H7.
            eapply REACH_Store; try eassumption.
              intros. rewrite getBlocks_char in H7. 
              destruct H7.
              destruct H7; try contradiction; subst.
              inv H4. eapply (restrictD_Some _ _ _ _ _ H13).
          split; intros.
            eapply FWD. eapply SMV; assumption.
            eapply assign_loc_forward; try eassumption. eapply SMV; assumption.

      (*by_copy*)
        destruct EffStep' as [b2' [ofs2' [X2 EffStep']]]; subst x2.
        eexists. eexists. exists mu.
        split. eexists.
               split. apply effstep_plus_one. eassumption.
        clear EffStep'.
        simpl. intros. 
        destruct (eq_block b b2); subst; simpl in *; try discriminate.
        inv H4.
        destruct (valid_block_dec m2 b2); simpl in *. rewrite andb_true_r in H2.
        Focus 2. rewrite andb_false_r in H2. inv H2.
        split; intros.
          eapply visPropagateR; eassumption.
        assert (WR:Mem.perm m loc (Int.unsigned ofs) Cur Writable).
                      eapply Mem.storebytes_range_perm; try eassumption.
                         rewrite (Mem.loadbytes_length _ _ _ _ _ H10).
                         specialize (sizeof_pos (typeof a1)); intros.
                         rewrite nat_of_Z_eq.
                         omega. omega.
        exists loc, delta.
        split. eapply restrict_vis_foreign; try eassumption.
          destruct (restrictD_Some _ _ _ _ _ H5).
          specialize (Mem.address_inject _ _ _ loc ofs b2 delta Writable INJ WR H12). intros.
          rewrite H14 in *.
          unfold assign_loc_Effect. rewrite H6. 
          destruct (eq_block loc loc); simpl. 
          clear e0. destruct (zle (Int.unsigned ofs + delta) ofs0); simpl in *; try discriminate.
                               destruct (zle (Int.unsigned ofs) (ofs0 - delta)); simpl.
                               Focus 2. exfalso. clear - l g. omega.
                               specialize (sizeof_pos (typeof a1)); intros.
                               destruct (zlt ofs0 (Int.unsigned ofs + delta + sizeof (typeof a1))); try discriminate.
                               destruct (zlt (ofs0 - delta) (Int.unsigned ofs + sizeof (typeof a1))); simpl.  
                                 split; trivial.
                                 eapply Mem.perm_implies. 
                                   eapply Mem.perm_max.
                                    eapply Mem.storebytes_range_perm; eauto.
                                     split. omega. rewrite (Mem.loadbytes_length _ _ _ _ _ H10). rewrite nat_of_Z_eq. assumption. omega. 
                                  apply perm_any_N.
                               exfalso. clear - l1 g. omega.
                   elim n; trivial. 
        clear H9 EffStep'.
        intuition. 
        apply intern_incr_refl. 
        apply sm_inject_separated_same_sminj.
        apply sm_locally_allocatedChar.
          repeat split; extensionality b.
          rewrite Freshloc. intuition.
          rewrite (assign_loc_freshloc _ _ _ _ _ _ AL2). intuition.
          rewrite Freshloc. intuition.
          rewrite (assign_loc_freshloc _ _ _ _ _ _ AL2). intuition.
        econstructor.
          econstructor; eauto. reflexivity. constructor.
          destruct (restrictD_Some _ _ _ _ _ H5).
          intuition.
          clear AL2.
            inv H4. destruct (restrictD_Some _ _ _ _ _ H17).
            eapply REACH_Storebytes; try eassumption.
            simpl; intros.
            destruct (Mem.loadbytes_inject _ _ _ _ _ _ _ _ _ MinjR H10 H17) as [bytes' [_ MVInj]].
            clear H10 H11.
            induction MVInj; simpl in *. contradiction.
            destruct H15; subst. 
              inv H10. eapply (restrictD_Some _ _ _ _ _ H19).
              apply (IHMVInj H11).
          split; intros.
            eapply FWD. eapply SMV; assumption.
            eapply assign_loc_forward; try eassumption. eapply SMV; assumption. }

{ (*clight_corestep_set*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      try (monadInv TR).
      inv MTR. destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      exploit transl_expr_correctMu; try eassumption.
        intros [uu [VinjU EvalX0]].
      eexists; eexists. exists mu.
      split. eexists; split. 
             apply effstep_plus_one.
               econstructor. eassumption.
               intuition.
      intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
        eapply match_tempenv_set; eassumption.
      intuition. }

{ (*clight_corestep_call*)
      destruct MC as [SMC PRE].
      inv SMC; simpl in *. 
      revert TR. simpl. case_eq (classify_fun (typeof a)); try congruence.
      intros targs tres CF TR. monadInv TR. inv MTR. 
      exploit functions_translated; eauto. intros [tfd [FIND TFD]].
      rewrite H in CF. simpl in CF. inv CF.
      destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
      exploit transl_expr_correctMu; try eassumption.
        intros [tvf [VinjE EvalE]].
      exploit transl_arglist_correctMu; try eassumption.
        intros [tvl [Vargs EvalArgs]].
      inv VinjE; inv FIND.
      destruct (Int.eq_dec ofs1 Int.zero); try inv H6.
      destruct (GF _ _ H2).
      destruct (restrictD_Some _ _ _ _ _ H4).
      rewrite H8 in H5; inv H5. 
      eexists; eexists. exists mu.
      split. eexists; split. 
               apply effstep_plus_one.
                 econstructor; try eassumption.
                 eapply transl_fundef_sig1; eauto.
                 rewrite H3. auto.
               intuition.
      intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto.    
          econstructor.
      intuition. }

{ (* builtin *)
    destruct MC as [SMC PRE].
    inv SMC; simpl in *. 
    monadInv TR. inv MTR.
    destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
    assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m m2).
      eapply inject_restrict; eassumption.
    assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
      rewrite <- restrict_sm_all. 
      eapply restrict_sm_preserves_globals; try eassumption.
      unfold vis. intuition. 
    exploit transl_arglist_correctMu; try eassumption.
    intros [tvargs [EVAL2 VINJ2]].
    exploit (inlineable_extern_inject _ _ GDE_lemma); 
       try eapply H0; try eassumption. 
    intros [mu' [vres' [tm' [EC [VINJ [MINJ' [UNMAPPED [OUTOFREACH 
           [INCR [SEPARATED [LOCALLOC [WD' [VAL' RC']]]]]]]]]]]]].
    eexists; eexists; eexists mu'.
    split. eexists.
      split. apply effstep_plus_one.
             econstructor; eassumption.
      intros. eapply BuiltinEffect_Propagate; eassumption. 
    intuition.
    split. assert (INC:= intern_incr_restrict _ _ WD' INCR).
           econstructor; eauto.
           Focus 5. eapply match_cont_inject_incr; eassumption.
           reflexivity. constructor.
           eapply match_env_inject_incr; eassumption.
           assert (TENV':= match_tempenv_inject_incr _ _ _ TENV _ INC).
           destruct optid; trivial; simpl.
           eapply match_tempenv_set; eassumption.
         intuition.
         eapply meminj_preserves_incr_sep. eapply PG. eassumption. 
             apply intern_incr_as_inj; trivial.
             apply sm_inject_separated_mem; eassumption.
         red. intros b fbb Hb. destruct (GF _ _ Hb).
           split; trivial.
           eapply intern_incr_as_inj; eassumption.
         assert (FRG: frgnBlocksSrc mu = frgnBlocksSrc mu') by eapply INCR.
           rewrite <- FRG. apply Glob; assumption. }

{ (* seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *. 
  monadInv TR. inv MTR.
  eexists; eexists. exists mu.
  split. eexists; split. 
           apply effstep_plus_one.
             constructor.
           intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto.  
      intuition. }

{ (* skip seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split. 
           apply effstep_plus_one.
           apply csharpmin_effstep_skip_seq.
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
      intuition. }

{ (* continue seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split. 
           apply effstep_plus_one.
             econstructor; eauto.
           intuition. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* break seq *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split. 
           apply effstep_plus_one.
             econstructor; eauto.
           intuition. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* ifthenelse *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  exploit make_boolean_inject; eauto.
      eapply inject_restrict; eassumption.
      assert (PGR': meminj_preserves_globals ge (as_inj (restrict_sm mu (vis mu)))).
              eapply restrict_sm_preserves_globals; try eassumption.
              unfold vis. intuition. 
           rewrite restrict_sm_all in PGR'. assumption.
  intros [tv [Etv Btv]].  
  exploit transl_expr_correctMu; try eassumption.
        intros [tv1 [V1inj EvalV1]].
  eexists; eexists. exists mu.
  split. eexists; split. 
           apply effstep_plus_one. 
           apply csharpmin_effstep_ifthenelse with (v := tv) (b := b); auto.
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality bb; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        destruct b; econstructor; eauto; constructor.
      intuition. }

{ (* loop *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. 
  exists (CSharpMin_State tf x
     (Kblock (Kseq x0 (Kseq (Sloop (Sseq (Sblock x) x0)) (Kblock tk)))) te tle).
  eexists. exists mu.
  split. 
  eexists; split. 
    eapply effstep_star_plus_trans.
      eapply match_transl_effstep; eauto. 
    eapply effstep_plus_star_trans.
      eapply effstep_plus_one.
        econstructor.
    eapply effstep_star_trans.
      eapply effstep_star_one.
        econstructor.
      eapply effstep_star_one.
        econstructor.
    intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; try eassumption.
          econstructor.
          econstructor; eassumption. 
      intuition. }

{ (* skip-or-continue loop *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  assert ((ts' = Sskip \/ ts' = Sexit ncnt) /\ tk' = tk).
    destruct H; subst x; monadInv TR; inv MTR; auto.
  destruct H0. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           eapply effstep_plus_star_trans.
             destruct H0; subst ts'.
               Focus 2. eapply effstep_plus_one. econstructor.
               eapply effstep_plus_one. econstructor.
             eapply effstep_star_one.
               econstructor.
           intuition. 
  clear H0 H.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.
        econstructor; eauto. 
        econstructor; eauto. 
      intuition. }

{ (* break loop1 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           eapply effstep_plus_star_trans.
             eapply effstep_plus_one. econstructor.
           eapply effstep_star_trans.
             eapply effstep_star_one.
               econstructor. 
           eapply effstep_star_trans.
             eapply effstep_star_one.
               econstructor. 
             eapply effstep_star_one.
               econstructor. 
        intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* skip loop2 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one. constructor.
           intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; eauto.    
          simpl. rewrite H5; simpl. rewrite H7; simpl. eauto. 
          constructor. 
      intuition. }

{ (* break loop2 *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           eapply effstep_plus_trans.
             eapply effstep_plus_one. constructor.
             eapply effstep_plus_one. constructor. 
           intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* return none *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]]. 
  exploit match_env_free_blocks_parallel_inject; eauto.
      eapply inject_restrict; eassumption.
    intros [m2' [FL2 Inj']].   
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one. constructor. eassumption.
         intros b2 ofs FEff2.
         split. 
           apply FreelistEffect_exists_FreeEffect in FEff2.
           destruct FEff2 as [bb [lo [hi [NIB FEF]]]].
           apply FreeEffectD in FEF. destruct FEF as [? [VB Arith2]]; subst.
           apply blocks_of_envD in NIB. destruct NIB as [? [id ID]]; subst.
           apply (me_local_inv _ _ _ MENV) in ID. destruct ID as [b [ty [RES EE]]].
           eapply visPropagateR; try eassumption.
         intros. eapply FreelistEffect_PropagateLeft; eassumption.
  assert (SMV': sm_valid mu m' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H); intuition.
      econstructor.
        econstructor; eauto.
          eapply match_cont_call_cont. eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* return some *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m m2).
      eapply inject_restrict; eassumption.
  assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
     rewrite <- restrict_sm_all. 
     eapply restrict_sm_preserves_globals; try eassumption.
     unfold vis. intuition. 
  exploit match_env_free_blocks_parallel_inject; eauto.
    intros [m2' [FL2 Inj']].
  destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV InjR 
            PGR _ _ H _ EQ) as [tv [VInj EvalA]].
  destruct (sem_cast_inject _ _ _ _ _ _ H0 VInj) as [tv' [SemCast' VInj']].
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             constructor; try eassumption.
             eapply make_cast_correct; eauto.
         intros b2 ofs FEff2.
         split. 
           apply FreelistEffect_exists_FreeEffect in FEff2.
           destruct FEff2 as [bb [lo [hi [NIB FEF]]]].
           apply FreeEffectD in FEF. destruct FEF as [? [VB Arith2]]; subst.
           apply blocks_of_envD in NIB. destruct NIB as [? [id ID]]; subst.
           apply (me_local_inv _ _ _ MENV) in ID. destruct ID as [b [ty [RES EE]]].
           eapply visPropagateR; try eassumption.
         intros. eapply FreelistEffect_PropagateLeft; eassumption.
  assert (SMV': sm_valid mu m' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H1); intuition.
      econstructor.
        econstructor; eauto.
          eapply match_cont_call_cont. eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* skip call *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  exploit match_cont_is_call_cont; eauto. intros [A B].
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m m2).
      eapply inject_restrict; eassumption.
  destruct (match_env_free_blocks_parallel_inject _ _ _ _ _ _ MENV InjR H0) as [m2' [FL2 Inj']].
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             apply csharpmin_effstep_skip_call. auto.
             eassumption.
         intros b2 ofs FEff2.
         split. 
           apply FreelistEffect_exists_FreeEffect in FEff2.
           destruct FEff2 as [bb [lo [hi [NIB FEF]]]].
           apply FreeEffectD in FEF. destruct FEF as [? [VB Arith2]]; subst.
           apply blocks_of_envD in NIB. destruct NIB as [? [id ID]]; subst.
           apply (me_local_inv _ _ _ MENV) in ID. destruct ID as [b [ty [RES EE]]].
           eapply visPropagateR; try eassumption.
         intros. eapply FreelistEffect_PropagateLeft; eassumption. 
  assert (SMV': sm_valid mu m' m2').
    split; intros;  
      eapply freelist_forward; try eassumption.
      eapply SMV; assumption.
      eapply SMV; assumption.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_free_list _ _ _ FL2);
          try rewrite (freshloc_free_list _ _ _ H0); intuition.
      econstructor.
        econstructor; eauto.
      intuition. 
        eapply REACH_closed_freelist; eassumption.
        eapply freelist_freelist_inject; try eassumption.
          eapply match_env_restrictD; eassumption. }

{ (* switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  assert (InjR: Mem.inject (restrict (as_inj mu) (vis mu)) m m2).
      eapply inject_restrict; eassumption.
  assert (PGR: meminj_preserves_globals ge (restrict (as_inj mu) (vis mu))).
     rewrite <- restrict_sm_all. 
     eapply restrict_sm_preserves_globals; try eassumption.
     unfold vis. intuition. 
  destruct (transl_expr_correct _ _ _ _ _ _ _ MENV TENV InjR 
            PGR _ _ H _ EQ) as [tv [VInj EvalA]].
  inv VInj.

  eexists; eexists. exists mu.
  split. eexists; split.
           eapply effstep_star_plus_trans.
             eapply match_transl_effstep; eauto.
           eapply effstep_plus_one.
             econstructor. eauto.
        intuition. 
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        econstructor; try eassumption.
          apply transl_lbl_stmt_2. apply transl_lbl_stmt_1. eauto.  
          constructor.
          econstructor. eauto.
      intuition. }

{ (* skip or break switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  assert ((ts' = Sskip \/ ts' = Sexit nbrk) /\ tk' = tk).
    destruct H; subst x; monadInv TR; inv MTR; auto.
  destruct H0. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             destruct H0; subst ts'.
              2: constructor. constructor.
         intuition.
  clear H0 H. 
  intuition.
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      econstructor.
        eapply match_states_skip; eauto.
      intuition. }

{ (* continue switch *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. inv MK.
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             constructor.
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. simpl. reflexivity. constructor.
      intuition. }

{ (* label *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR. 
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             constructor. 
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. constructor.
      intuition. }

{ (* goto *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  monadInv TR. inv MTR.
  generalize TRF. unfold transl_function. intro TRF'. monadInv TRF'.
  exploit (transl_find_label lbl). eexact EQ.
  eapply match_cont_call_cont. eauto.
  rewrite H. 
  intros [ts' [tk'' [nbrk' [ncnt' [A [B C]]]]]].
  eexists; eexists. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             constructor. simpl. eexact A. 
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. constructor.
      intuition. }

{ (* internal function *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  destruct PRE as [PC [PG [GF [Glob [SMV [WD INJ]]]]]].
  inv H. monadInv TR. monadInv EQ.
  exploit match_cont_is_call_cont; eauto. intros [A B].
  exploit match_env_alloc_variables; try eassumption. 
    apply match_env_empty.
  intros [te1 [m2' [mu' [AVars2 [MENV' [INJ' [INC'
         [SEP' [LAC' [WD' [VAL' RC']]]]]]]]]]].
  specialize (create_undef_temps_match_inject 
         (Clight.fn_temps f) (restrict (as_inj mu') (vis mu'))); intros. 
  destruct (bind_parameter_temps_match_inject
       _ _ _ _ H4 _ _ H args2)
     as [tle [BP TENV]].
     eapply val_list_inject_incr; try eassumption.
       eapply intern_incr_restrict; eassumption.
  eexists; exists m2'. exists mu'.
  split. eexists; split.
           apply effstep_plus_one.
             eapply csharpmin_effstep_internal_function.
           simpl. rewrite list_map_compose. simpl. assumption.
           simpl. auto.
           simpl. auto.
           simpl. eauto.
           simpl. eassumption.
        intuition.
  intuition.
    constructor.
      simpl. econstructor; try eassumption.
         unfold transl_function. rewrite EQ0; simpl. auto.         
         constructor.
         eapply match_cont_inject_incr; try eassumption.
           eapply intern_incr_restrict; eassumption.
    destruct (@intern_incr_meminj_preserves_globals_as_inj _ _ ge _ WD) with (mu' := mu').
        split; trivial. trivial. trivial.
    intuition.
       red; intros. destruct (GF _ _ H8). split; trivial.
           eapply intern_incr_as_inj; eassumption. }

{ (* returnstate *)
  destruct MC as [SMC PRE].
  inv SMC; simpl in *.
  inv MK. 
  eexists; exists m2. exists mu.
  split. eexists; split.
           apply effstep_plus_one.
             constructor.
         intuition.
  intuition. 
      apply intern_incr_refl. 
      apply sm_inject_separated_same_sminj.
      apply sm_locally_allocatedChar.
      repeat split; extensionality b; 
          try rewrite (freshloc_irrefl); intuition.
      constructor. 
        econstructor; eauto. simpl; reflexivity. 
           constructor.
        unfold set_opttemp. 
        destruct optid. 
          eapply match_tempenv_set; eassumption.
          simpl. assumption.
      intuition. }
Qed.

Lemma match_cont_replace_locals: forall mu tp n m k k' PS PT
        (MC: match_cont (as_inj mu) tp n m k k'), 
        match_cont (as_inj (replace_locals mu PS PT)) tp n m k k'.
Proof. intros.
  rewrite replace_locals_as_inj; trivial.
Qed.

Lemma MATCH_atExternal:
forall (mu : SM_Injection) (c1 : CL_core) (m1 : mem) 
     (c2 : CSharpMin_core) (m2 : mem) (e : external_function)
     (vals1 : list val) (ef_sig : signature),
   MATCH c1 mu c1 m1 c2 m2 ->
   at_external (CL_eff_sem2 hf) c1 = Some (e, ef_sig, vals1) ->
   Mem.inject (as_inj mu) m1 m2 /\
   (exists vals2 : list val,
      Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2 /\
      at_external (csharpmin_eff_sem hf) c2 = Some (e, ef_sig, vals2) /\
      (forall pubSrc' pubTgt' : block -> bool,
       pubSrc' =
       (fun b : block =>
        locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b) ->
       pubTgt' =
       (fun b : block =>
        locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b) ->
       forall nu : SM_Injection,
       nu = replace_locals mu pubSrc' pubTgt' ->
       MATCH c1 nu c1 m1 c2 m2 /\ Mem.inject (shared_of nu) m1 m2)).
Proof. intros. destruct H as [MC [RC [PG [GFP [Glob [SMV [WD INJ]]]]]]].
    split; trivial.
    destruct c1; inv H0. destruct fd; inv H1.
    inv MC. simpl in TY. inv TY.     
    specialize (val_list_inject_forall_inject _ _ _ ArgsInj). intros ValsInj.
    specialize (forall_vals_inject_restrictD _ _ _ _ ValsInj); intros.
    exploit replace_locals_wd_AtExternal; try eassumption. 
    intros WDr.
    remember (observableEF_dec hf e0) as d. 
    destruct d; inv H0.
    rename o into OBS.
    exists args2; intuition.
      destruct tfd; simpl in *.
        remember ( list_typ_eq (sig_args (ef_sig e)) (typlist_of_typelist targs) &&
           opt_typ_eq (sig_res (ef_sig e)) (opttyp_of_type tres)) as q.
        destruct q; inv TR.
      remember ( list_typ_eq (sig_args (ef_sig e)) (typlist_of_typelist targs) &&
           opt_typ_eq (sig_res (ef_sig e)) (opttyp_of_type tres)) as q.
        destruct q; inv TR.
        rewrite <- Heqd. trivial.
     (*MATCH*)
       split; subst; rewrite replace_locals_as_inj, replace_locals_vis. 
         econstructor; repeat rewrite restrict_sm_all, vis_restrict_sm, 
            replace_locals_vis, replace_locals_as_inj in *; eauto.
         simpl. reflexivity. 
       rewrite replace_locals_frgnBlocksSrc. intuition.
       (*sm_valid*)
         red. rewrite replace_locals_DOM, replace_locals_RNG. apply SMV.
    (*Shared*)
      eapply inject_shared_replace_locals; try eassumption.
      subst; trivial.
Qed.

(** The simulation proof *)
Theorem transl_program_correct:
  forall (R: list_norepet (map fst (prog_defs prog)))
         (init_mem: exists m0, Genv.init_mem prog = Some m0),
SM_simulation.SM_simulation_inject (CL_eff_sem2 hf)
   (csharpmin_eff_sem hf) ge tge.
Proof.
intros.
 eapply effect_simulations_lemmas.inj_simulation_plus with
  (match_states:=MATCH) (measure:=fun x => O).
(*genvs_dom_eq*)
  apply GDE_lemma.
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
(*MATCHinitial*)
  { intros.
    eapply (MATCH_initial _ _ _); eauto.
    destruct init_mem as [m0 INIT].
    exists m0; split; auto.
    unfold meminj_preserves_globals in H3.    
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
    assert (VB: Mem.valid_block m1 (Mem.nextblock m1)).
      eapply Mem.valid_block_inject_1; eauto.
    clear - VB; unfold Mem.valid_block in VB.
    xomega.

    destruct (P (Mem.nextblock m0) (Mem.nextblock m2)); auto.
    exfalso. 
    destruct (D _ p).
    apply A in H2.
    assert (VB: Mem.valid_block m2 (Mem.nextblock m2)).
      eapply Mem.valid_block_inject_2; eauto.
    clear - VB; unfold Mem.valid_block in VB.
    xomega.
    
    intros b LT.    
    unfold ge. 
    apply valid_init_is_global with (b0 := b) in INIT.
    eapply INIT; auto.
    apply R.
    apply LT. apply GDE_lemma. }
(*halted*) 
  { intros. destruct H as [MC [RC [PG [GF [Glob [VAL [WD INJ]]]]]]]. 
    destruct c1; inv H0. destruct k; inv H1.
    inv MC. exists res2.
    split. assumption.
    split. eassumption.
    simpl. inv MK. trivial. }
(* at_external*)
  { apply MATCH_atExternal. }
(* after_external*)
  { apply MATCH_afterExternal. apply GDE_lemma. }
(* core_diagram*)
  { intros. exploit MATCH_corediagram; try eassumption.
    intros [st2' [m2' [mu' [CS2 MU']]]].
    exists st2', m2', mu'. intuition. }
(* effcore_diagram*)
 { intros. exploit Match_effcore_diagram; try eassumption.
    intros [st2' [m2' [mu' [[U2 CS2] MU']]]].
    exists st2', m2', mu'. intuition.
    exists U2. split. left; assumption. assumption. }
Qed.

End CORRECTNESS.
