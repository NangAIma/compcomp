Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Values.
Require Import Memory.
Require Import Globalenvs.
Require Import Events.
Require Import Smallstep.
Require Import Op.
Require Import Locations.
Require Import Conventions.
Require Stacklayout.

Require Import Mach. 
Require Import Stacking.

Require Import mem_lemmas. (*for mem_forward*)
Require Import core_semantics.
Require Import val_casted.

Definition genv := Genv.t fundef unit.

Notation "a ## b" := (List.map a b) (at level 1).
Notation "a # b <- c" := (Regmap.set b c a) (at level 1, b at next level).

Inductive load_frame: Type :=
| mk_load_frame:
    forall (sp: block)       (**r pointer to argument frame *)
           (args: list val)  (**r initial program arguments *)
           (tys: list typ),  (**r initial argument types *)
    load_frame.

Section RELSEM.

Variable return_address_offset: function -> code -> int -> Prop.

Variable ge: genv.

Inductive Mach_core: Type :=
  | Mach_State:
      forall (stack: list stackframe)  (**r call stack *)
             (f: block)                (**r pointer to current function *)
             (sp: val)                 (**r stack pointer *)
             (c: code)                 (**r current program point *)
             (rs: regset)              (**r register state *)
             (loader: load_frame),     (**r program loader frame *)
      Mach_core

  | Mach_Callstate:
      forall (stack: list stackframe)  (**r call stack *)
             (f: block)                (**r pointer to function to call *)
             (rs: regset)              (**r register state *)
             (loader: load_frame),     (**r program loader frame *)
      Mach_core

  (*Auxiliary state: for marshalling arguments INTO memory*)
  | Mach_CallstateIn: 
      forall (f: block)                (**r pointer to function to call *)
             (args: list val)          (**r arguments passed to initial_core *)
             (tys: list typ),          (**r argument types *)
      Mach_core

  (*Auxiliary state: for marshalling arguments OUT OF memory*)
  | Mach_CallstateOut: 
      forall (stack: list stackframe)  (**r call stack *)
             (b: block)                (**r global block address of the external 
                                            function to be called*)
             (f: external_function)    (**r external function to be called *)
             (vals: list val)          (**r at_external arguments *)
             (rs: regset)              (**r register state *)
             (loader: load_frame),     (**r program loader frame *)
      Mach_core

  | Mach_Returnstate:
      forall (stack: list stackframe)  (**r call stack *)
             (retty: option typ)       (**r optional return register int-floatness *)
             (rs: regset)              (**r register state *)
             (loader: load_frame),     (**r program loader frame *)
      Mach_core.

(*NOTE [store_args] store_args is used to model program loading of
  initial arguments.  Cf. NOTE [loader] below. *)

Fixpoint store_args (sp: val) (ofs: Z) (args: list val) (tys: list typ) (m: mem) 
         : option mem :=
  match args,tys with
    | nil,nil => Some m
    | a::args',ty::tys' => 
      match store_stack m sp ty (Int.repr (Stacklayout.fe_ofs_arg + 4*ofs)) a with
        | None => None
        | Some m' => store_args sp (ofs+1) args' tys' m'
      end
    | _,_ => None
  end.

Lemma store_stack_fwd m sp t i a m' :
  store_stack m sp t i a = Some m' -> 
  mem_forward m m'.
Proof.
unfold store_stack, Mem.storev.
destruct (Val.add sp (Vint i)); try solve[inversion 1].
apply store_forward.
Qed.

Lemma store_args_fwd sp ofs args tys m m' :
  store_args sp ofs args tys m = Some m' -> 
  mem_forward m m'.
Proof.
revert tys ofs m; induction args.
simpl. destruct tys. intros ofs. inversion 1; subst. 
solve[apply mem_forward_refl].
intros ofs. solve[inversion 1].
destruct tys. solve[inversion 1].
inversion 1. revert H1.
generalize
  (Int.repr
     match ofs with
       | 0 => 0
       | Z.pos y' => Z.pos y'~0~0
       | Z.neg y' => Z.neg y'~0~0
     end) as i; intro.
case_eq (store_stack m sp t i a); [|solve[intros; congruence]].
intros m0 H2 H3.
apply store_stack_fwd in H2. 
apply IHargs in H3.
eapply mem_forward_trans; eauto.
Qed.

Lemma store_stack_unch_on stk z t i a m m' :
  store_stack m (Vptr stk z) t i a = Some m' ->
  Mem.unchanged_on (fun b ofs => b<>stk) m m'.
Proof.
unfold store_stack, Mem.storev. 
case_eq (Val.add (Vptr stk z) (Vint i)); try solve[inversion 1].
intros b i0 H H2. eapply Mem.store_unchanged_on in H2; eauto.
intros i2 H3 H4. inv H. apply H4; auto.
Qed.

Lemma store_args_unch_on stk z ofs args tys m m' :
  store_args (Vptr stk z) ofs args tys m = Some m' -> 
  Mem.unchanged_on (fun b ofs => b<>stk) m m'.
Proof.
revert ofs tys m; induction args.
simpl. destruct tys. inversion 1; subst. 
  solve[apply Mem.unchanged_on_refl].
solve[inversion 1].
destruct tys. solve[inversion 1].
inversion 1. revert H1.
generalize (Int.repr
             match ofs with
               | 0 => 0
               | Z.pos y' => Z.pos y'~0~0
               | Z.neg y' => Z.neg y'~0~0
             end) as ofs'. intros ofs'.
case_eq (store_stack m (Vptr stk z) t ofs' a). 
intros m2 H2 H3.
eapply unchanged_on_trans with (m2 := m2); eauto.
solve[eapply store_stack_unch_on; eauto].
solve[apply store_stack_fwd in H2; auto].
solve[inversion 2].
Qed.

Inductive mach_step: Mach_core -> mem -> Mach_core -> mem -> Prop :=
  | Mach_exec_Mlabel:
      forall s f sp lbl c rs m lf,
      mach_step (Mach_State s f sp (Mlabel lbl :: c) rs lf) m
                (Mach_State s f sp c rs lf) m

  | Mach_exec_Mgetstack:
      forall s f sp ofs ty dst c rs m v lf,
      load_stack m sp ty ofs = Some v ->
      mach_step (Mach_State s f sp (Mgetstack ofs ty dst :: c) rs lf) m
                (Mach_State s f sp c (rs#dst <- v) lf) m

  | Mach_exec_Msetstack:
      forall s f sp src ofs ty c rs m m' rs' lf,
      store_stack m sp ty ofs (rs src) = Some m' ->
      rs' = undef_regs (destroyed_by_setstack ty) rs ->
      mach_step (Mach_State s f sp (Msetstack src ofs ty :: c) rs lf) m
                (Mach_State s f sp c rs' lf) m'

  | Mach_exec_Mgetparam:
      forall s fb f sp ofs ty dst c rs m v rs' args0 tys0 sp0,
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      load_stack m sp Tint f.(fn_link_ofs) = Some (parent_sp s) ->
      load_stack m (parent_sp s) ty ofs = Some v ->
      rs' = (rs # temp_for_parent_frame <- Vundef # dst <- v) ->
      mach_step (Mach_State s fb sp (Mgetparam ofs ty dst :: c) rs (mk_load_frame args0 tys0 sp0)) m
                (Mach_State s fb sp c rs' (...)) m

  | Mach_exec_Mop:
      forall s f sp op args res c rs m v rs' lf,
      eval_operation ge sp op rs##args m = Some v ->
      rs' = ((undef_regs (destroyed_by_op op) rs)#res <- v) ->
      mach_step (Mach_State s f sp (Mop op args res :: c) rs lf) m
                (Mach_State s f sp c rs' lf) m

  | Mach_exec_Mload:
      forall s f sp chunk addr args dst c rs m a v rs' lf,
      eval_addressing ge sp addr rs##args = Some a ->
      Mem.loadv chunk m a = Some v ->
      rs' = ((undef_regs (destroyed_by_load chunk addr) rs)#dst <- v) ->
      mach_step (Mach_State s f sp (Mload chunk addr args dst :: c) rs lf) m
                (Mach_State s f sp c rs' lf) m

  | Mach_exec_Mstore:
      forall s f sp chunk addr args src c rs m m' a rs' lf,
      eval_addressing ge sp addr rs##args = Some a ->
      Mem.storev chunk m a (rs src) = Some m' ->
      rs' = undef_regs (destroyed_by_store chunk addr) rs ->
      mach_step (Mach_State s f sp (Mstore chunk addr args src :: c) rs lf) m
                (Mach_State s f sp c rs' lf) m'

  (*NOTE [loader]*)
  | Mach_exec_Minitialize_call: 
      forall m args tys m1 stk m2 fb,
      Mem.alloc m 0 (4*Zlength args) = (m1, stk) ->
      let sp := Vptr stk Int.zero in
      store_args sp 0 args tys m1 = Some m2 -> 
      mach_step (Mach_CallstateIn fb args tys) m
        (Mach_Callstate nil fb (Regmap.init Vundef) (mk_load_frame stk args tys)) m2

  | Mach_exec_Mcall_internal:
      forall s fb sp sig ros c rs m f f' ra callee lf,
      find_function_ptr ge ros rs = Some f' ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      return_address_offset f c ra ->
      (*NEW: check that the block f' actually contains a (internal) function:*)
      Genv.find_funct_ptr ge f' = Some (Internal callee) ->
      mach_step (Mach_State s fb sp (Mcall sig ros :: c) rs lf) m
                (Mach_Callstate (Stackframe fb sp (Vptr fb ra) c :: s) f' rs lf) m

  | Mach_exec_Mcall_external:
      forall s fb sp sig ros c rs m f f' ra callee args lf,
      find_function_ptr ge ros rs = Some f' ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      return_address_offset f c ra ->
      (*NEW: check that the block f' actually contains a (external)
             function, and perform the "extra step":*)
      Genv.find_funct_ptr ge f' = Some (External callee) ->
      extcall_arguments rs m sp (ef_sig callee) args ->
      mach_step (Mach_State s fb sp (Mcall sig ros :: c) rs lf) m
                (Mach_CallstateOut (Stackframe fb sp (Vptr fb ra) c :: s) 
                  f' callee args rs lf) m

  | Mach_exec_Mtailcall_internal:
      forall s fb stk soff sig ros c rs m f f' m' callee lf,
      find_function_ptr ge ros rs = Some f' ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      load_stack m (Vptr stk soff) Tint f.(fn_link_ofs) = Some (parent_sp s) ->
      load_stack m (Vptr stk soff) Tint f.(fn_retaddr_ofs) = Some (parent_ra s) ->
      Mem.free m stk 0 f.(fn_stacksize) = Some m' ->
      (*NEW: check that the block f' actually contains a function:*)
      Genv.find_funct_ptr ge f' = Some (Internal callee) ->
      mach_step (Mach_State s fb (Vptr stk soff) (Mtailcall sig ros :: c) rs lf) m
                (Mach_Callstate s f' rs lf) m'

  | Mach_exec_Mtailcall_external:
      forall s fb stk soff sig ros c rs m f f' m' callee args lf,
      find_function_ptr ge ros rs = Some f' ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      load_stack m (Vptr stk soff) Tint f.(fn_link_ofs) = Some (parent_sp s) ->
      load_stack m (Vptr stk soff) Tint f.(fn_retaddr_ofs) = Some (parent_ra s) ->
      Mem.free m stk 0 f.(fn_stacksize) = Some m' ->
      (*NEW: check that the block f' actually contains a function:*)
      Genv.find_funct_ptr ge f' = Some (External callee) ->
      extcall_arguments rs m' (parent_sp s) (ef_sig callee) args ->
      mach_step (Mach_State s fb (Vptr stk soff) (Mtailcall sig ros :: c) rs lf) m
                (Mach_CallstateOut s f' callee args rs lf) m'

  | Mach_exec_Mbuiltin:
      forall s f sp rs m ef args res b t vl rs' m' lf,
      external_call' ef ge rs##args m t vl m' ->
      rs' = set_regs res vl (undef_regs (destroyed_by_builtin ef) rs) ->
      mach_step (Mach_State s f sp (Mbuiltin ef args res :: b) rs lf) m
                (Mach_State s f sp b rs' lf) m'

(*NO SUPPORT FOR ANNOT YET
  | Mach_exec_Mannot:
      forall s f sp rs m ef args b vargs t v m',
      annot_arguments rs m sp args vargs ->
      external_call' ef ge vargs m t v m' ->
      mach_step (Mach_State s f sp (Mannot ef args :: b) rs) m
         t (Mach_State s f sp b rs) m'*)

  | Mach_exec_Mgoto:
      forall s fb f sp lbl c rs m c' lf,
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      find_label lbl f.(fn_code) = Some c' ->
      mach_step (Mach_State s fb sp (Mgoto lbl :: c) rs lf) m
                (Mach_State s fb sp c' rs lf) m

  | Mach_exec_Mcond_true:
      forall s fb f sp cond args lbl c rs m c' rs' lf,
      eval_condition cond rs##args m = Some true ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      find_label lbl f.(fn_code) = Some c' ->
      rs' = undef_regs (destroyed_by_cond cond) rs ->
      mach_step (Mach_State s fb sp (Mcond cond args lbl :: c) rs lf) m
                (Mach_State s fb sp c' rs' lf) m

  | Mach_exec_Mcond_false:
      forall s f sp cond args lbl c rs m rs' lf,
      eval_condition cond rs##args m = Some false ->
      rs' = undef_regs (destroyed_by_cond cond) rs ->
      mach_step (Mach_State s f sp (Mcond cond args lbl :: c) rs lf) m
                (Mach_State s f sp c rs' lf) m

  | Mach_exec_Mjumptable:
      forall s fb f sp arg tbl c rs m n lbl c' rs' lf,
      rs arg = Vint n ->
      list_nth_z tbl (Int.unsigned n) = Some lbl ->
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      find_label lbl f.(fn_code) = Some c' ->
      rs' = undef_regs destroyed_by_jumptable rs ->
      mach_step (Mach_State s fb sp (Mjumptable arg tbl :: c) rs lf) m
                (Mach_State s fb sp c' rs' lf) m

  | Mach_exec_Mreturn:
      forall s fb stk soff c rs m f m' lf,
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      load_stack m (Vptr stk soff) Tint f.(fn_link_ofs) = Some (parent_sp s) ->
      load_stack m (Vptr stk soff) Tint f.(fn_retaddr_ofs) = Some (parent_ra s) ->
      Mem.free m stk 0 f.(fn_stacksize) = Some m' ->
      mach_step (Mach_State s fb (Vptr stk soff) (Mreturn :: c) rs lf) m
                (Mach_Returnstate s (sig_res (fn_sig f)) rs lf) m'

  | Mach_exec_function_internal:
      forall s fb rs m f m1 m2 m3 stk rs' lf,
      Genv.find_funct_ptr ge fb = Some (Internal f) ->
      Mem.alloc m 0 f.(fn_stacksize) = (m1, stk) ->
      let sp := Vptr stk Int.zero in
      store_stack m1 sp Tint f.(fn_link_ofs) (parent_sp s) = Some m2 ->
      store_stack m2 sp Tint f.(fn_retaddr_ofs) (parent_ra s) = Some m3 ->
      rs' = undef_regs destroyed_at_function_entry rs ->
      mach_step (Mach_Callstate s fb rs lf) m
                (Mach_State s fb sp f.(fn_code) rs' lf) m3

  | Mach_exec_return:
      forall s f sp ra c retty rs m lf,
      mach_step (Mach_Returnstate (Stackframe f sp ra c :: s) retty rs lf) m
                (Mach_State s f sp c rs lf) m.

End RELSEM.

Definition Mach_initial_core (ge:genv) (v: val) (args:list val)
           : option Mach_core := 
  match v with
    | Vptr b i => 
      if Int.eq_dec i Int.zero 
      then match Genv.find_funct_ptr ge b with
             | None => None
             | Some f => 
               match f with 
                 | Internal fi =>
                   let tyl := sig_args (funsig f) in
                   if val_has_type_list_func args (sig_args (funsig f))
                      && vals_defined args
                   then Some (Mach_CallstateIn b (encode_longs tyl args) tyl)
                   else None
                 | External _ => None
               end
           end
      else None
    | _ => None
   end.

(*NOTE Halted when the stack contains just a single stack frame 
  (modeling the program loader)*)

Definition Mach_halted (q : Mach_core): option val :=
    match q with 
      (*Return Tlong, which must be decoded*)
      | Mach_Returnstate nil (Some Tlong) rs lf => 
           match loc_result (mksignature nil (Some Tlong)) with
             | nil => None
             | r1 :: r2 :: nil => 
                 match decode_longs (Tlong::nil) (rs r1::rs r2::nil) with
                   | v :: nil => Some v
                   | _ => None
                 end
             | _ => None
           end

      (*Return a value of any other typ*)
      | Mach_Returnstate nil (Some retty) rs lf => 
           match loc_result (mksignature nil (Some retty)) with
            | nil => None
            | r :: TL => match TL with 
                           | nil => Some (rs r)
                           | _ :: _ => None
                         end
           end

      (*Return Tvoid - modeled as integer return*)
      | Mach_Returnstate nil None rs lf => Some (rs AX)

      | _ => None
    end.

Definition Mach_at_external (c: Mach_core):
          option (external_function * signature * list val) :=
  match c with
  | Mach_State _ _ _ _ _ _ => None
  | Mach_Callstate _ _ _ _ => None
  | Mach_CallstateIn _ _ _ => None
  | Mach_CallstateOut s fb ef args rs lf => 
      Some (ef, ef_sig ef, decode_longs (sig_args (ef_sig ef)) args)
  | Mach_Returnstate _ _ _ _ => None
 end.

Definition Mach_after_external (vret: option val)(c: Mach_core) : option Mach_core :=
  match c with 
    Mach_CallstateOut s fb ef args rs lf => 
      match vret with
            | None => Some (Mach_Returnstate s (sig_res (ef_sig ef))
                             (set_regs (loc_result (ef_sig ef))
                               (encode_long (sig_res (ef_sig ef)) Vundef) rs)
                             lf)
            | Some v => Some (Mach_Returnstate s (sig_res (ef_sig ef))
                               (set_regs (loc_result (ef_sig ef))
                                 (encode_long (sig_res (ef_sig ef)) v) rs)
                               lf)
          end
  | _ => None
  end.

Lemma Mach_at_external_halted_excl :
       forall q, Mach_at_external q = None \/ Mach_halted q = None.
   Proof. intros. destruct q; auto. Qed.

Lemma Mach_after_at_external_excl : forall retv q q',
      Mach_after_external retv q = Some q' -> Mach_at_external q' = None.
  Proof. intros.
    destruct q; simpl in *; try inv H.
    destruct retv; inv H1; simpl; trivial.
  Qed.

Section MACH_CORESEM.
Variable return_address_offset: function -> code -> int -> Prop.

Lemma Mach_corestep_not_at_external:
       forall ge m q m' q', mach_step return_address_offset ge q m q' m' -> 
              Mach_at_external q = None.
Proof. intros. inv H; try reflexivity. Qed.

Lemma Mach_corestep_not_halted : forall ge m q m' q', 
       mach_step return_address_offset ge q m q' m' -> 
       Mach_halted q = None.
Proof. intros. inv H; auto. Qed.

Definition Mach_core_sem : CoreSemantics genv Mach_core mem.
  eapply (@Build_CoreSemantics _ _ _ 
            Mach_initial_core
            Mach_at_external
            Mach_after_external
            Mach_halted
            (mach_step return_address_offset)).
    apply Mach_corestep_not_at_external.
    apply Mach_corestep_not_halted.
    apply Mach_at_external_halted_excl.
Defined.

End MACH_CORESEM.

(******NOW SHOW THAT WE ALSO HAVE A COOPSEM******)

Section MACH_COOPSEM.
Variable return_address_offset: function -> code -> int -> Prop.

Lemma Mach_forward : forall g c m c' m'
         (CS: mach_step return_address_offset g c m c' m'), 
         mem_forward m m'.
  Proof. intros.
   inv CS; try apply mem_forward_refl.
   (*Msetstack*)
     unfold store_stack in H; simpl in *.
     destruct sp; inv H.
     eapply store_forward; eassumption. 
   (*Mstore*)
     destruct a; simpl in H0; inv H0. 
     eapply store_forward. eassumption. 
   (*initialize*)
     eapply store_args_fwd in H0.
     eapply mem_forward_trans; eauto.
     solve[eapply alloc_forward; eauto].
   (*Mtailcall_internal*)
     eapply free_forward; eassumption.
   (*Mtailcall_external*)
     eapply free_forward; eassumption.
   (*Mbuiltin**)
      inv H.
      eapply external_call_mem_forward; eassumption.
    (*Mannot
      inv H. 
      eapply external_call_mem_forward; eassumption.*)
    (*Mreturn*)
      eapply free_forward; eassumption.
    (*internal function*)
     unfold store_stack in *; simpl in *.
     eapply mem_forward_trans.
       eapply alloc_forward; eassumption.
     eapply mem_forward_trans.
       eapply store_forward; eassumption. 
       eapply store_forward; eassumption. 
Qed.

Program Definition Mach_coop_sem : 
  CoopCoreSem genv Mach_core.
apply Build_CoopCoreSem with (coopsem := Mach_core_sem return_address_offset).
  apply Mach_forward.
Defined.

End MACH_COOPSEM.