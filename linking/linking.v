Require Import Axioms.

Require Import sepcomp. Import SepComp.

Require Import pos.
Require Import stack. 
Require Import core_semantics_tcs.

Require Import ssreflect ssrbool ssrnat ssrfun eqtype seq fintype finfun.
Set Implicit Arguments.

(*NOTE: because of redefinition of [val], these imports must appear 
  after Ssreflect eqtype.*)
Require Import AST.    (*for typ*)
Require Import Values. (*for val*)
Require Import Globalenvs. 
Require Import Integers.

Require Import ZArith.

(* This file is a parametric version of [compcert_linking.v].  See that   *)
(* file for more information.                                             *)

Module CoreLinker (Csem : CORESEM).

(* The [CoreLinker] module gives the operational semantics of linking.    *)
(* It is parameterized by the type of core semantics [Csem] (e.g., effect *)
(* semantics, coop semantics, vanilla core semantics) used to the dynamic *)
(* semantics of each translation unit.  Note that each module may still   *)
(* have its own core type C, function definition type F, etc.             *)

(* Semantics of translation units *)

Module Modsem. 

Record t := mk
  { F   : Type
  ; V   : Type
  ; ge  : Genv.t F V
  ; C   : Type
  ; sem : Csem.t (Genv.t F V) C
  ; init : C }.

End Modsem.

(* [Cores] are runtime execution units. *)

Module Core. Section core.

Variable N : pos.
Variable cores : 'I_N -> Modsem.t.

Import Modsem.

Record t := mk
  { i  : 'I_N
  ; c  :> (cores i).(C) 
  ; sg : signature }.

Definition upd (core : t) (newC : (cores core.(i)).(C)) :=
  {| i := core.(i)
   ; c := newC 
   ; sg := core.(sg) |}.

End core. End Core.

Arguments Core.t {N} cores.

Arguments Core.i {N cores} !t /.

Arguments Core.c {N cores} !t /.

Arguments Core.sg {N cores} !t /.

Arguments Core.upd {N cores} !core _ /.

(* Linking semantics invariants:                                          *)
(*  -All cores except the topmost one are at_external.                    *)
(*  -The call stack always contains at least one core.                    *)

Import Coresem.

Section coreDefs.

Import Modsem.

Variable N : pos.
Variable cores : 'I_N -> Modsem.t.

Definition atExternal (c: Core.t cores) :=
  let: (Core.mk i c sg) := c in
  let: F := (cores i).(F) in
  let: V := (cores i).(V) in
  let: C := (cores i).(C) in
  let: sem := (cores i).(sem) in
  if @at_external (Genv.t F V) C Csem.M (Csem.instance (T:=sem)) c is 
    Some (ef, dep_sig, args) then true
  else false.

Definition wf_callStack (stk : Stack.t (Core.t cores)) := 
  [&& all atExternal (STACK.pop stk) & size stk > 0].

End coreDefs.

Arguments atExternal {N} cores c.

(** Call stacks are [stack]s satisfying the [wf_callStack] invariant. *)

Module CallStack. Section callStack.

Context {N : pos} (cores : 'I_N -> Modsem.t).

Record t : Type := mk
  { callStack :> Stack.t (Core.t cores)
  ; _         :  wf_callStack callStack }.

Program Definition singl (core: Core.t cores) := mk [:: core] _.

Section callStackDefs.

Context (stack : t).

Definition callStackSize := size stack.(callStack).

Lemma callStack_wf : wf_callStack stack.
Proof. by case: stack. Qed.

Lemma callStack_ext : all (atExternal cores) (STACK.pop stack).
Proof. by move: callStack_wf; move/andP=> [H1 H2]. Qed.

Lemma callStack_size : callStackSize > 0.
Proof. by move: callStack_wf; move/andP=> [H1 H2]. Qed.

Lemma callStack_nonempty : STACK.nonempty stack.
Proof. by case: stack=> //; case. Qed.

End callStackDefs. 

End callStack. End CallStack.

(* [Linker.t]                                                             *)
(*                                                                        *)
(*  The first two fields of this record are static configuration data:    *)
(*                                                                        *)
(*    -[cores] is a function from module id's ('I_n, or integers in the   *)
(*     range [0..n-1]) to genvs and core semantics, with existentially    *)
(*     quantified core type [C].                                          *)
(*                                                                        *)
(*    -[fn_tbl] maps external function id's to module id's                *)
(*                                                                        *)
(*  [stack] is used to maintain a stack of cores, at runtime.             *)
(*  Parameter [N] is the number of static modules in the program.         *)

Module Linker. Section linker.

Variable N : pos.
Variable cores : 'I_N  -> Modsem.t.

Record t := mkLinker 
  { fn_tbl : ident -> option 'I_N
  ; stack  :> CallStack.t cores }.

End linker. End Linker.

Import Linker.

Notation linker := Linker.t.

Section linkerDefs.

Context {N : pos} (my_cores : 'I_N -> Modsem.t) (l : linker N my_cores).

Import CallStack. (*for coercion [callStack]*)

Definition updStack (newStack : CallStack.t my_cores) :=
  {| fn_tbl := l.(fn_tbl)
   ; stack  := newStack |}.

(* [inContext]: The top core on the call stack has a return context  *)     

Definition inContext (l0 : linker N my_cores) := callStackSize l0.(stack) > 1.

(* [updCore]: Replace the top core on the call stack with [newCore]  *)     

Program Definition updCore (newCore: Core.t my_cores) := 
  updStack (CallStack.mk (STACK.push (STACK.pop l.(stack)) newCore) _).  
Next Obligation. apply/andP; split=>/=; last by []; by apply: callStack_ext. Qed.

Lemma updCore_inj newCore newCore' : 
  updCore newCore = updCore newCore' -> newCore=newCore'.
Proof. by case. Qed.

Lemma updCore_inj_upd c c1 c2 : 
  updCore (Core.upd c c1) = updCore (Core.upd c c2) -> c1=c2.
Proof. 
case=> H1; move: (EqdepFacts.eq_sigT_snd H1); move=> <-. 
by rewrite -Eqdep.Eq_rect_eq.eq_rect_eq.
Qed.

(* [pushCore]: Push a new core onto the call stack.                       *)
(* Succeeds only if all cores are currently at_external.                  *)

Lemma stack_push_wf newCore :
  all (atExternal my_cores) l.(stack).(callStack) -> 
  wf_callStack (SeqStack.updStack (newCore :: l.(stack).(callStack))).
Proof.
by rewrite/wf_callStack=> H; apply/andP; split.
Qed.

Definition pushCore 
  (newCore: Core.t my_cores) 
  (pf : all (atExternal my_cores) l.(stack).(callStack)) := 
  updStack (CallStack.mk (STACK.push l.(stack) newCore) (stack_push_wf _ pf)).

(* [popCore]: Pop the top core on the call stack.                         *)
(* Succeeds only if the top core is running in a return context.          *)

Lemma inContext_wf (stk : Stack.t (Core.t my_cores)) : 
  size stk > 1 -> wf_callStack stk -> wf_callStack (STACK.pop stk).
Proof.
rewrite/wf_callStack=> H1; move/andP=> [H2 H3]; apply/andP; split.
- by apply: STACK.all_pop.
- by move: H1 H2 H3; case: stk.
Qed.

Program Definition popCore : option (linker N my_cores) := 
  (match inContext l as pf 
         return (pf = inContext l -> option (linker N my_cores)) with
    | true => fun pf => 
        Some (updStack (CallStack.mk (STACK.pop l.(stack)) 
                                     (inContext_wf _ _ _)))
    | false => fun pf => None
  end) Logic.eq_refl.
Next Obligation. by apply: callStack_wf. Qed.

Definition peekCore := STACK.head l.(stack) (callStack_nonempty l.(stack)).

Definition emptyStack := if l.(stack).(callStack) is [::] then true else false.

Import Modsem.

Definition initCore (sg: signature) (ix: 'I_N) (v: val) (args: list val) 
  : option (Core.t my_cores):=
  if @initial_core _ _ _ 
       (Csem.instance (T:=(my_cores ix).(sem)))
       (my_cores ix).(Modsem.ge) 
       v args 
  is Some c then Some (Core.mk _ my_cores ix c sg)
  else None.

End linkerDefs.

Notation ge_ty := (Genv.t unit unit).

Arguments updStack {N} {my_cores} !_ _ /.

Arguments updCore {N} {my_cores} !_ _ /.

Arguments pushCore {N} {my_cores} !l _ _ /.

Arguments peekCore {N} {my_cores} !l /.

Arguments emptyStack {N} {my_cores} !l /.

(** The linking semantics *)

Module LinkerSem. Section linkerSem.

Variable N : pos.  (* Number of (compile-time) modules *)
Variable my_cores : 'I_N  -> Modsem.t.
Variable my_fn_tbl: ident -> option 'I_N.

(* [handle id l args] looks up function id [id] in function table         *)
(* [l.fn_tbl], producing an optional module index [ix : 'I_N].  The index *)
(* is used to construct a new core to handle the call to function         *)
(* [id]. The new core is pushed onto the call stack.                      *)

Section handle.

Variables (sg: signature) (id: ident) (l: linker N my_cores) (args: list val).

Import CallStack.

Definition handle :=
  (match all (atExternal my_cores) l.(stack).(callStack) as pf 
        return (pf = all (atExternal my_cores) l.(stack).(callStack) 
               -> option (linker N my_cores)) with
    | true => fun pf => 
        if l.(fn_tbl) id is Some ix then
        if Genv.find_symbol (my_cores ix).(Modsem.ge) id is Some bf then
        if initCore my_cores sg ix (Vptr bf Int.zero) args is Some c 
          then Some (pushCore l c (Logic.eq_sym pf))
        else None else None else None
    | false => fun _ => None
  end) erefl.

End handle.

Section handle_lems.

Import CallStack.

Lemma handleP sg id l args l' :
  handle sg id l args = Some l' <-> 
  (exists (pf : all (atExternal my_cores) l.(stack).(callStack)) ix bf c,
     [/\ l.(fn_tbl) id = Some ix 
       , Genv.find_symbol (my_cores ix).(Modsem.ge) id = Some bf
       , initCore my_cores sg ix (Vptr bf Int.zero) args = Some c
       & l' = pushCore l c pf]).
Proof.
rewrite/handle.
rewrite /pushCore.
generalize (stack_push_wf l).
pattern (all (atExternal my_cores) (CallStack.callStack (stack l)))
 at 1 2 3 4 5 6 7 8 9.
case f: (all _ _); move=> pf.
case g: (fn_tbl l id)=> [ix|].
case fnd: (Genv.find_symbol _ _)=> [bf|].
case h: (initCore _ _ _)=> [c|].
split=> H.
exists (erefl true),ix,bf,c; split=> //; first by case: H=> <-.
case: H=> pf0 []ix0 []bf0 []c0 []; case=> <-.
rewrite fnd; case=> <-; rewrite h; case=> <- ->. 
by repeat f_equal; apply: proof_irr.
split=> //; case=> pf0 []ix0 []bf0 []c0 []. 
by case=> <-; rewrite fnd; case=> <-; rewrite h.
split=> //; case=> pf0 []ix0 []bf0 []c0 [].
by case=> <-; rewrite fnd; discriminate.
split=> //.
by case=> pf0 []ix0 []bf0 []c0 []; discriminate.
split=> //.
by case=> pf0 []ix0 []bf0 []c0 []; discriminate.
Qed.

End handle_lems.

Definition main_sig := mksignature nil (Some Tint).

Definition initial_core (tt: ge_ty) (v: val) (args: list val)
  : option (linker N my_cores) :=
  if v is Vptr id ofs then 
  if my_fn_tbl id is Some ix then
  if initCore my_cores main_sig ix (Vptr id Int.zero) args is Some c 
  then Some (mkLinker my_fn_tbl (CallStack.singl c))
  else None else None else None.

(* Functions suffixed w/ 0 always operate on the running core on the (top *)
(* of the) call stack.                                                    *)

Definition at_external0 (l: linker N my_cores) :=
  let: c   := peekCore l in
  let: ix  := c.(Core.i) in
  let: sem := (my_cores ix).(Modsem.sem) in
  let: F   := (my_cores ix).(Modsem.F) in
  let: V   := (my_cores ix).(Modsem.V) in
    @at_external (Genv.t F V) _ _ (Csem.instance (T:=sem)) (Core.c c).

Arguments at_external0 !l.

Require Import val_casted. (*for val_has_type_func*)

Definition halted0 (l: linker N my_cores) :=
  let: c   := peekCore l in
  let: ix  := c.(Core.i) in
  let: sg  := c.(Core.sg) in
  let: sem := (my_cores ix).(Modsem.sem) in
  let: F   := (my_cores ix).(Modsem.F) in
  let: V   := (my_cores ix).(Modsem.V) in
    if @halted (Genv.t F V) _ _ (Csem.instance (T:=sem)) (Core.c c) is Some v then
      if val_casted.val_has_type_func v (proj_sig_res sg) then Some v
      else None
    else None.

Arguments halted0 !l.

(* [corestep0] lifts a corestep of the runing core to a corestep of the   *)
(* whole program semantics.                                               *)

Definition corestep0 
  (l: linker N my_cores) (m: Csem.M) (l': linker N my_cores) (m': Csem.M) := 
  let: c   := peekCore l in
  let: ix  := c.(Core.i) in
  let: sem := (my_cores ix).(Modsem.sem) in
  let: F   := (my_cores ix).(Modsem.F) in
  let: V   := (my_cores ix).(Modsem.V) in
  let: ge  := (my_cores ix).(Modsem.ge) in
    exists c', 
      @corestep (Genv.t F V) _ _ (Csem.instance (T:=sem)) ge (Core.c c) m c' m'
   /\ l' = updCore l (Core.upd c c').

Arguments corestep0 !l m l' m'.

Definition fun_id (ef: external_function) : option ident :=
  if ef is (EF_external id sig) then Some id else None.

(* The linker is [at_external] whenever the top core is [at_external] and *)
(* the [id] of the called external function isn't handleable by any       *)
(* compilation unit.                                                      *)

Definition at_external (l: linker N my_cores) :=
  if at_external0 l is Some (ef, dep_sig, args) 
    then if fun_id ef is Some id then
         if fn_tbl l id is None then Some (ef, dep_sig, args) else None
         else None
  else at_external0 l.

Definition after_external (mv: option val) (l: linker N my_cores) :=
  let: c   := peekCore l in
  let: ix  := c.(Core.i) in
  let: sem := (my_cores ix).(Modsem.sem) in
  let: F   := (my_cores ix).(Modsem.F) in
  let: V   := (my_cores ix).(Modsem.V) in
  let: ge  := (my_cores ix).(Modsem.ge) in
    if @after_external (Genv.t F V) _ _ (Csem.instance (T:=sem)) mv (Core.c c) 
      is Some c' then Some (updCore l (Core.upd c c'))
    else None.

(* The linker is [halted] when the last core on the call stack is halted. *)

Definition halted (l: linker N my_cores) := 
  if ~~inContext l then 
  if halted0 l is Some rv then Some rv
  else None else None.

(* Corestep relation of linking semantics *)

Definition corestep 
  (l: linker N my_cores) (m: Csem.M)
  (l': linker N my_cores) (m': Csem.M) := 

  (** 1- The running core takes a step, or *)
  corestep0 l m l' m' \/

  (** 2- We're in a function call context. In this case, the running core is either *)
  (m=m' 
   /\ ~corestep0 l m l' m' 
   /\ 
      (** 3- at_external, in which case we push a core onto the stack to handle 
         the external function call (or this is not possible because no module 
         handles the external function id, in which case the entire linker is 
         at_external) *)

      if at_external0 l is Some (ef, dep_sig, args) then
      if fun_id ef is Some id then
      if handle (ef_sig ef) id l args is Some l'' then l'=l'' else False else False
      else 

      (** 4- or halted, in which case we pop the halted core from the call stack
         and inject its return value into the caller's corestate. *)

      if inContext l then 
      if halted0 l is Some rv then
      if popCore l is Some l0 then 
      if after_external (Some rv) l0 is Some l'' then l'=l'' 
      else False else False else False

     else False).

Inductive Corestep : linker N my_cores -> Csem.M
                  -> linker N my_cores -> Csem.M -> Prop :=
| Corestep_step : 
  forall l m c' m',
  let: c     := peekCore l in
  let: c_ix  := Core.i c in
  let: c_ge  := Modsem.ge (my_cores c_ix) in
  let: c_sem := Modsem.sem (my_cores c_ix) in
    core_semantics.corestep (Csem.instance (T:=c_sem)) c_ge (Core.c c) m c' m' -> 
    Corestep l m (updCore l (Core.upd (peekCore l) c')) m'

| Corestep_call :
  forall (l : linker N my_cores) m ef dep_sig args id bf d_ix d
         (pf : all (atExternal my_cores) (CallStack.callStack l)),

  let: c := peekCore l in
  let: c_ix  := Core.i c in
  let: c_ge  := Modsem.ge (my_cores c_ix) in
  let: c_sem := Modsem.sem (my_cores c_ix) in

  core_semantics.at_external (Csem.instance (T:=c_sem)) (Core.c c) = Some (ef,dep_sig,args) -> 
  fun_id ef = Some id -> 
  fn_tbl l id = Some d_ix -> 
  Genv.find_symbol (my_cores d_ix).(Modsem.ge) id = Some bf -> 

  let: d_ge  := Modsem.ge (my_cores d_ix) in
  let: d_sem := Modsem.sem (my_cores d_ix) in

  core_semantics.initial_core (Csem.instance (T:=d_sem)) d_ge (Vptr bf Int.zero) args = Some d -> 
  Corestep l m (pushCore l (Core.mk _ _ _ d (ef_sig ef)) pf) m

| Corestep_return : 
  forall (l : linker N my_cores) l'' m rv d',

  1 < CallStack.callStackSize (stack l) -> 

  let: c  := peekCore l in
  let: c_ix  := Core.i c in
  let: c_sg  := Core.sg c in
  let: c_ge  := Modsem.ge (my_cores c_ix) in
  let: c_sem := Modsem.sem (my_cores c_ix) in

  popCore l = Some l'' -> 

  let: d  := peekCore l'' in     
  let: d_ix  := Core.i d in
  let: d_ge  := Modsem.ge (my_cores d_ix) in
  let: d_sem := Modsem.sem (my_cores d_ix) in

  core_semantics.halted (Csem.instance (T:=c_sem)) (Core.c c) = Some rv -> 
  val_has_type_func rv (proj_sig_res c_sg)=true -> 
  core_semantics.after_external (Csem.instance (T:=d_sem)) (Some rv) (Core.c d) = Some d' -> 
  Corestep l m (updCore l'' (Core.upd d d')) m.

Lemma CorestepE l m l' m' : 
  Corestep l m l' m' -> 
  corestep l m l' m'.
Proof.
inversion 1; subst; rename H0 into A; rename H into B.
by left; exists c'; split.
right; split=> //.
split=> //.
rewrite /corestep0=> [][]c' []step.
by rewrite /= (corestep_not_at_external _ _ _ _ _ step) in A.
rewrite /= in A.
rewrite /inContext /at_external0 A H1.
case e: (handle _ _ _)=> //[l'|].
move: e; case/handleP=> pf' []ix' []bf' []c []C G D ->.
move: D; rewrite /initCore.
rewrite H2 in C; case: C=> eq; subst ix'.
rewrite G in H3; case: H3=> ->.
by rewrite /= in H4; rewrite H4; case=> <-; f_equal; apply: proof_irr.
move: e; rewrite/handle /pushCore.
generalize (stack_push_wf l).
pattern (all (atExternal my_cores) (CallStack.callStack (stack l))) 
 at 1 2 3 4 5 6 7.
case f: (all _ _)=> pf'.
rewrite /= in H4; rewrite H2 H3 /initCore H4; discriminate.
by rewrite pf in f.
right; split=> //.
split=> //.
rewrite /corestep0=> [][]c' []step.
by rewrite /= (corestep_not_halted _ _ _ _ _ step) in H2.
have at_ext: 
  core_semantics.at_external
    (Csem.instance (T:=(Modsem.sem (my_cores (Core.i (peekCore l))))))
    (Core.c (peekCore l)) = None.
{ case: (@at_external_halted_excl _ _ _
         (Csem.instance (T:=(Modsem.sem (my_cores (Core.i (peekCore l))))))
         (Core.c (peekCore l)))=> //.
  by rewrite /= in H2; rewrite H2. }
rewrite /= in at_ext; rewrite /inContext A /at_external0 H1 at_ext.
by rewrite /= in H2 H4; rewrite /halted0 H2 /after_external H3 H4. 
Qed.

Lemma CorestepI l m l' m' : 
  corestep l m l' m' -> 
  Corestep l m l' m'.
Proof.
case.
case=> c []step ->.
by apply: Corestep_step.
case=> <-.
case=> nstep.
case atext: (at_external0 _)=> [[[ef dep_sig] args]|//].
case funid: (fun_id ef)=> [id|//].
case hdl:   (handle (ef_sig ef) id l args)=> [l''|//] ->.
move: hdl; case/handleP=> pf []ix []bf []c []fntbl genv init ->.
move: init; rewrite /initCore.
case init: (Coresem.initial_core _ _ _)=> [c'|//]; case=> <-. 
by apply: (@Corestep_call _ _ ef dep_sig args id).
case inCtx: (inContext _)=> //.
case hlt: (halted0 _)=> [rv|//].
case pop: (popCore _)=> [c|//].
case aft: (after_external _ _)=> [l''|//] ->.
move: aft; rewrite /after_external.
case aft: (Coresem.after_external _ _)=> [c''|//]. 
rewrite /halted0 in hlt; move: hlt.
case hlt: (Coresem.halted _)=> //. 
case oval: (val_has_type_func _ _)=> //; case=> Heq. subst. case=> <-.
by apply: (@Corestep_return _ _ _ rv c'').
Qed.

Lemma CorestepP l m l' m' : 
  corestep l m l' m' <-> Corestep l m l' m'.
Proof. by split; [apply: CorestepI | apply: CorestepE]. Qed.

Lemma corestep_not_at_external0 m c m' c' :
  corestep0 c m c' m' -> at_external0 c = None.
Proof. by move=>[]newCore []H1 H2; apply corestep_not_at_external in H1. Qed.

Lemma at_external_halted_excl0 c : at_external0 c = None \/ halted0 c = None.
Proof.
case: (@at_external_halted_excl _ _ _
        (Csem.instance (T:=(Modsem.sem (my_cores (Core.i (peekCore c))))))
        (Core.c (peekCore c))).
by rewrite /at_external0=> ->; left.
by rewrite /halted0=> ->; right.
Qed.

Lemma corestep_not_halted0 m c m' c' : corestep0 c m c' m' -> halted c = None.
Proof.
move=> []newCore []H1 H2; rewrite/halted.
case Hcx: (~~ inContext _)=>//; case Hht: (halted0 _)=>//.
by move: Hht; rewrite/halted0; apply corestep_not_halted in H1; rewrite /= H1.
Qed.

Lemma corestep_not_at_external (ge : ge_ty) m c m' c' : 
  corestep c m c' m' -> at_external c = None.
Proof.
rewrite/corestep/at_external.
move=> [H|[_ [_ H]]]; first by move: H; move/corestep_not_at_external0=> /= ->.
move: H; case Heq: (at_external0 c)=>[[[ef sig] args]|//].
move: Heq; case: (at_external_halted_excl0 c)=> [H|H]; first by rewrite H.
move=> H2; case: (fun_id ef)=>// id; case hdl: (handle _ _ _)=> [a|].
by move: hdl; case/handleP=> ? []? []? []? []->.
by [].
Qed.

Lemma at_external0_not_halted c x :
  at_external0 c = Some x -> halted c = None.
Proof.
case: (at_external_halted_excl0 c); rewrite/at_external0/halted.
by case Heq: (peekCore c)=>//[a] ->.
move=> H; case Heq: (peekCore c)=>//[a]. 
by case Hcx: (~~ inContext _)=>//; rewrite H.
Qed.

Lemma corestep_not_halted (ge : ge_ty) m c m' c' :
  corestep c m c' m' -> halted c = None.
Proof. 
rewrite/corestep.
move=> [H|[_ [_ H]]]; first by move: H; move/corestep_not_halted0.
move: H; case Hat: (at_external0 _)=> [x|//].
by rewrite (at_external0_not_halted _ Hat).
by rewrite /halted; case Hcx: (inContext _).
Qed.

Lemma at_external_halted_excl c :
  at_external c = None \/ halted c = None.
Proof.
rewrite/at_external/halted; case Hat: (at_external0 c)=>//; 
first by right; apply: (at_external0_not_halted _ Hat). 
by left.
Qed.

Definition coresem : CoreSemantics ge_ty (linker N my_cores) Csem.M :=
  Build_CoreSemantics ge_ty (linker N my_cores) Csem.M 
    initial_core
    at_external
    after_external
    halted 
    (fun _ : ge_ty => corestep)
    corestep_not_at_external    
    corestep_not_halted 
    at_external_halted_excl.

End linkerSem. End LinkerSem.

End CoreLinker.

Module Linker := CoreLinker EffectsemCore. Import Linker.
Module Sem    := Linker.LinkerSem.

(* Specialize to effect semantics *)

Section effingLinker.

Variable N : pos. 
Variable my_cores : 'I_N -> Modsem.t. 
Variable my_fun_tbl : ident -> option 'I_N.

Import Linker.

Definition effstep0 U (l: linker N my_cores) m (l': linker N my_cores) m' := 
  let: c   := peekCore l in
  let: ix  := c.(Core.i) in
  let: sem := (my_cores ix).(Modsem.sem) in
  let: F   := (my_cores ix).(Modsem.F) in
  let: V   := (my_cores ix).(Modsem.V) in
  let: ge  := (my_cores ix).(Modsem.ge) in
    exists c', 
      @effstep (Genv.t F V) _ sem ge U (Core.c c) m c' m'
   /\ l' = updCore l (Core.upd c c').

Lemma effstep0_unchanged U l m l' m' : 
  effstep0 U l m l' m' ->
  Memory.Mem.unchanged_on (fun b ofs => U b ofs = false) m m'.
Proof. 
rewrite/effstep0; case=> ? [STEP].
by move: {STEP}(effax1 STEP)=> [STEP]UNCH H2.
Qed.

Lemma effstep0_corestep0 U l m l' m' : 
  effstep0 U l m l' m' -> Sem.corestep0 l m l' m'.
Proof. 
rewrite/effstep0/Sem.corestep0; case=> c' [STEP].
move: {STEP}(effax1 STEP)=> [STEP]UNCH H2.
by exists c'; split.
Qed.

Lemma effstep0_forward U l m l' m' : 
  effstep0 U l m l' m' -> mem_forward m m'.
Proof. 
move/effstep0_corestep0; rewrite/Sem.corestep0. 
by move=> []c' []STEP H1; apply: {STEP}(corestep_fwd STEP). 
Qed.

Definition inner_effstep (ge: ge_ty)
  (l: linker N my_cores) m (l': linker N my_cores) m' := 
  [/\ Sem.corestep l m l' m' 
    & Sem.corestep0 l m l' m' -> exists U, effstep0 U l m l' m'].

Definition effstep (ge: ge_ty) V
  (l: linker N my_cores) m (l': linker N my_cores) m' := 
  [/\ Sem.corestep l m l' m' 
    , Sem.corestep0 l m l' m' -> effstep0 V l m l' m'
    & ~Sem.corestep0 l m l' m' -> forall b ofs, ~~ V b ofs].

Section csem.

Notation mycsem := (Sem.coresem N my_cores my_fun_tbl).

Program Definition csem 
  : CoreSemantics ge_ty (linker N my_cores) Memory.Mem.mem := 
  Build_CoreSemantics _ _ _
    (initial_core mycsem)
    (at_external mycsem)
    (after_external mycsem)
    (halted mycsem) 
    inner_effstep _ _ _.

Next Obligation. 
move: H; rewrite/inner_effstep=> [[H1] H2]. 
by apply: (Sem.corestep_not_at_external _ H1).
Qed.

Next Obligation.
move: H; rewrite/inner_effstep=> [[H1] H2]. 
by apply: (Sem.corestep_not_halted _ H1).
Qed.

Next Obligation. by apply: (Sem.at_external_halted_excl). Qed.

End csem.

Program Definition coopsem := Build_CoopCoreSem _ _ csem _.

Next Obligation. 
move: CS; case; move=>[H1|[<- [H0 H1]]]. 
by move/(_ H1)=>{H1} [U EFF]; apply (effstep0_forward EFF).
by move=> ?; apply mem_forward_refl.
Qed.

Program Definition effsem := Build_EffectSem _ _ coopsem effstep _ _ _.

Next Obligation. 
move: H=>[H1]H2; split. 
by split=> //; move=> H3; move: {H2 H3}(H2 H3)=> STEP; exists M.
case: H1=> [H1|[<- [H0 H1]]]=> //. 
by move: (H2 H1)=> H3; apply: (effstep0_unchanged H3).
Qed.

Next Obligation.
move: H; rewrite/inner_effstep=> [[[H1|[<- [H0 H1]]]]] H2=> //.
move: (H2 H1)=> {H2}[U H3]; exists U; split=> //.
by left; apply: (effstep0_corestep0 H3).
by exists [fun _ _ => false]; split=> //; right.
Qed.

Next Obligation.
move: H; rewrite/effstep=> [][]; case.
move=> H; move/(_ H); rewrite/effstep0. 
by move=> []? []H2 _ _; apply: (effstep_valid _ _ _ _ _ _ _ H2 _ _ H0).
by move=> []_ []nstep _ _; move/(_ nstep b z); rewrite H0.
Qed.

End effingLinker.
