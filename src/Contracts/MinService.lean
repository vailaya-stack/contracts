import Contracts.Utils
import Mathlib.Tactic

/-!-/
namespace Contracts.MinService

structure MinServiceStructure (m : Type → Type) where
  maxElem {l : List ℕ} : l ≠ [] → m ℕ

class MinServiceContract (s : MinServiceStructure m) [Monad m] [ContractMonad m] : Type where
  maxElemIsElem {l : List ℕ} (h : l ≠ []) : Ensures (s.maxElem h) fun r => r ∈ l
  maxElemIsMax {l : List ℕ} (h : l ≠ []) : Ensures (s.maxElem h) fun r => ∀ a ∈ l, a ≤ r

attribute [grind →, contract] MinServiceContract.maxElemIsElem MinServiceContract.maxElemIsMax

end Contracts.MinService
