import Contracts.Utils
import Mathlib.Tactic

/-!-/
namespace Contracts.SortService

structure SortServiceStructure (m : Type → Type) where
  sortList : List ℕ → m (List ℕ)

class SortServiceContract (s : SortServiceStructure m) [Monad m] [ContractMonad m] : Type where
  isSorted : ∀ l, Ensures (s.sortList l) fun r => r.SortedLE
  isPerm : ∀ l, Ensures (s.sortList l) fun r => r.isPerm l

attribute [grind →, contract] SortServiceContract.isSorted SortServiceContract.isPerm

end Contracts.SortService
