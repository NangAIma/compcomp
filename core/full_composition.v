Require Import Events.
Require Import Memory.
Require Import Coqlib.
Require Import Values.
Require Import Maps.
Require Import Integers.
Require Import AST.
Require Import Globalenvs.
Require Import Axioms.

Require Import mem_lemmas. (*needed for definition of mem_forward etc*)

Require Import StructuredInjections.
Require Import reach.
Require Import Wellfounded.

Definition full_comp (j1 j2: meminj) :=  
  forall b0 b1 delta1, j1 b0 = Some (b1, delta1) -> exists b2 delta2, j2 b1 = Some (b2, delta2).

Definition full_ext (mu1 mu2: SM_Injection) :=
  full_comp (extern_of mu1) (extern_of mu2).