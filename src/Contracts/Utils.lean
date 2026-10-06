import Mathlib.Tactic.DefEqTransformations
import Batteries.Lean.LawfulMonad
import Lean.LabelAttribute

/-! What every contract is stated with: the monads a service may run in, what it means for a
call to ensure a property of its result, and the tactics that prove it. -/


namespace Contracts

register_label_attr contract

instance {ε σ : Type} : WeaklyLawfulMonadAttach (EST ε σ) where
  map_attach {α} {x} := by
    funext s
    simp only [Functor.map, EST.bind, MonadAttach.attach]
    split <;> rename_i h <;> split at h <;> cases h <;> simp [*, EST.pure]

instance {ε σ : Type} : LawfulMonadAttach (EST ε σ) where
  canReturn_map_imp {α P x a} := by
    rintro ⟨s, s', h⟩
    simp only [Functor.map, EST.bind] at h
    split at h <;> cases h
    exact (‹Subtype P›).property

instance {ε : Type} : LawfulMonadAttach (EIO ε) :=
  inferInstanceAs (LawfulMonadAttach (EST ε IO.RealWorld))

instance : LawfulMonadAttach IO :=
  inferInstanceAs (LawfulMonadAttach (EIO IO.Error))

class ContractMonad (m : Type → Type) [Monad m] extends
    MonadAttach m, LawfulMonad m, LawfulMonadAttach m

instance : ContractMonad Id where

instance {ε : Type} : ContractMonad (EIO ε) where

instance : ContractMonad IO where

abbrev Ensures {m : Type → Type} [Monad m] [ContractMonad m] {α : Type} (x : m α)
    (P : α → Prop) : Prop :=
  ∀ r, MonadAttach.CanReturn x r → P r

variable {m : Type → Type} [Monad m] [ContractMonad m] {α β : Type}

@[grind →]
theorem canReturn_pure {a b : α} (h : MonadAttach.CanReturn (pure a : m α) b) : a = b :=
  LawfulMonadAttach.eq_of_canReturn_pure h

@[grind →]
theorem canReturn_bind {x : m α} {f : α → m β} {b : β}
    (h : MonadAttach.CanReturn (x >>= f) b) :
    ∃ a, MonadAttach.CanReturn x a ∧ MonadAttach.CanReturn (f a) b :=
  LawfulMonadAttach.canReturn_bind_imp' h

@[grind →]
theorem canReturn_map {x : m α} {f : α → β} {b : β}
    (h : MonadAttach.CanReturn (f <$> x) b) : ∃ a, MonadAttach.CanReturn x a ∧ f a = b :=
  LawfulMonadAttach.canReturn_map_imp' h

@[grind →]
theorem canReturn_id {x : Id α} {b : α}
    (h : @MonadAttach.CanReturn Id ContractMonad.toMonadAttach α x b) : @Eq α x b := h

theorem Ensures.pure {a : α} {P : α → Prop} (h : P a) : Ensures (pure a : m α) P :=
  fun _ hr => canReturn_pure hr ▸ h

theorem Ensures.bind {x : m α} {f : α → m β} {Q : β → Prop}
    (h : ∀ r, MonadAttach.CanReturn x r → Ensures (f r) Q) : Ensures (x >>= f) Q := fun _ hb => by
  obtain ⟨a, ha, hb⟩ := canReturn_bind hb
  exact h a ha _ hb

theorem Ensures.map {x : m α} {f : α → β} {Q : β → Prop}
    (h : ∀ r, MonadAttach.CanReturn x r → Q (f r)) : Ensures (f <$> x) Q := fun _ hb => by
  obtain ⟨a, ha, rfl⟩ := canReturn_map hb
  exact h a ha

theorem Ensures.ite {c : Prop} [Decidable c] {x y : m α} {P : α → Prop}
    (hx : c → Ensures x P) (hy : ¬c → Ensures y P) : Ensures (if c then x else y) P := by
  split
  · exact hx ‹_›
  · exact hy ‹_›

theorem Ensures.dite {c : Prop} [Decidable c] {x : c → m α} {y : ¬c → m α} {P : α → Prop}
    (hx : ∀ h, Ensures (x h) P) (hy : ∀ h, Ensures (y h) P) : Ensures (dite c x y) P := by
  split
  · exact hx ‹_›
  · exact hy ‹_›

theorem Ensures.id {x : Id α} {P : α → Prop} (h : P x) : Ensures x P :=
  fun _ hr => hr ▸ h

open Lean Meta in
def contractFact? (thm : Name) (hr : FVarId) : MetaM (Option (Expr × Expr)) := do
  let c ← mkConstWithFreshMVarLevels thm
  let ty ← inferType c
  let hrTy ← instantiateMVars (← hr.getType)
  for k in [1:12] do
    let (args, binfos, concl) ← forallMetaTelescopeReducing ty (some k)
    if args.size < k then return none
    let last := args[k - 1]!
    unless (← instantiateMVars (← inferType last)).isAppOf ``MonadAttach.CanReturn do continue
    unless ← isDefEq (← inferType last) hrTy do return none
    last.mvarId!.assign (mkFVar hr)
    for a in args, b in binfos do
      if b.isInstImplicit && !(← a.mvarId!.isAssigned) then
        let some inst ← synthInstance? (← inferType a) | return none
        unless ← isDefEq a inst do return none
    let proof ← instantiateMVars (mkAppN c args)
    if proof.hasExprMVar then return none
    return some (proof, (← instantiateMVars concl).headBeta)
  return none

open Lean Meta Elab Tactic in
def stripResult (r hr : Name) : TacticM Unit := withMainContext do
  let some rDecl := (← getLCtx).findFromUserName? r | return
  let some hrDecl := (← getLCtx).findFromUserName? hr | return
  let mut g ← getMainGoal
  let mut found := false
  for thm in ← labelled `contract do
    let some (proof, fact) ← g.withContext (contractFact? thm hrDecl.fvarId) | continue
    let name := rDecl.userName.appendAfter ("_" ++ thm.getString!)
    g := (← (← g.assert name fact proof).intro1P).2
    found := true
  if found then g ← g.clear hrDecl.fvarId
  replaceMainGoal [g]

open Lean Elab Tactic Meta in
partial def ensuresIntro : TacticM Unit := withMainContext do
  let e ← instantiateMVars (← getMainTarget)
  unless e.isAppOfArity ``Ensures 6 do return
  let x := (e.getArg! 4).headBeta
  let r := mkIdent `r
  let hr := mkIdent `hr
  let hcond := mkIdent `hcond
  let introAll : TacticM Unit := do
    let mut out := []
    for g in ← getGoals do
      setGoals [g]; ensuresIntro; out := out ++ (← getGoals)
    setGoals out
  if x.isAppOfArity ``Bind.bind 6 then
    let f := (x.getArg! 5).headBeta
    let n := mkIdent (if f.isLambda then f.bindingName! else `r)
    let hn := mkIdent (n.getId.appendBefore "h")
    evalTactic (← `(tactic| refine Ensures.bind fun $n $hn => ?_))
    stripResult n.getId hn.getId
    ensuresIntro
  else if x.isAppOfArity ``Functor.map 6 then
    evalTactic (← `(tactic| refine Ensures.map fun $r $hr => ?_; beta_reduce))
    stripResult `r `hr
  else if x.isAppOfArity ``Pure.pure 4 then
    evalTactic (← `(tactic| refine Ensures.pure ?_; beta_reduce))
  else if x.isAppOfArity ``ite 5 then
    evalTactic (← `(tactic| refine Ensures.ite (fun $hcond => ?_) (fun $hcond => ?_)))
    introAll
  else if x.isAppOfArity ``dite 5 then
    evalTactic (← `(tactic| refine Ensures.dite (fun $hcond => ?_) (fun $hcond => ?_)))
    introAll
  else if (← isMatcherApp x) then
    evalTactic (← `(tactic| split))
    introAll
  else
    evalTactic (← `(tactic| first | refine Ensures.id ?_; beta_reduce | intro $r $hr))
    stripResult `r `hr

syntax "ensures_intro" (" [" ident,* "]")? : tactic

open Lean Elab Tactic in
elab_rules : tactic
  | `(tactic| ensures_intro $[[$ids?,*]]?) => do
    if let some ids := ids? then
      for id in ids.getElems do
        evalTactic (← `(tactic| simp only [$id:ident]))
    evalTactic (← `(tactic| try dsimp only))
    let mut out := []
    for g in ← getGoals do
      setGoals [g]; ensuresIntro; out := out ++ (← getGoals)
    setGoals out

end Contracts
