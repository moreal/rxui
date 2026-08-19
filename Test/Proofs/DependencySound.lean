import LeanRx.Proofs.DependencySound
import Test.Core.Expr

namespace LeanRxTest.DependencySound

open LeanRxTest.Expr

def left : LeanRx.Store Pricing := pricingStore 12 4 40
def sameDependencies : LeanRx.Store Pricing := pricingStore 12 4 999

/-- `subtotal` cannot observe `threshold`, whose field is outside its index. -/
theorem subtotal_ignores_threshold : subtotal.eval left = subtotal.eval sameDependencies := by
  apply LeanRx.RxExpr.eval_congr_on_deps
  intro _ field member
  cases field with
  | here => rfl
  | there field =>
      cases field with
      | here => rfl
      | there field =>
          cases field with
          | here =>
              have normalized : (LeanRx.DepSet.union
                  (LeanRx.DepSet.singleton price)
                  (LeanRx.DepSet.singleton quantity)).Contains
                    (LeanRx.Field.there (LeanRx.Field.there LeanRx.Field.here) :
                      LeanRx.Field Pricing Int) := by
                simpa only [subtotal, LeanRx.RxExpr.dependencies] using member
              have alternatives := (LeanRx.DepSet.hasId_union
                (LeanRx.Field.there (LeanRx.Field.there LeanRx.Field.here) :
                  LeanRx.Field Pricing Int).index _ _).1 normalized
              cases alternatives with
              | inl inPrice =>
                  have impossible :=
                    (LeanRx.DepSet.hasId_singleton _ price).1 inPrice
                  simp [price, LeanRx.Field.index] at impossible
              | inr inQuantity =>
                  have impossible :=
                    (LeanRx.DepSet.hasId_singleton _ quantity).1 inQuantity
                  simp [quantity, LeanRx.Field.index] at impossible
          | there field => exact nomatch field

def run : IO Unit := do
  unless subtotal.eval left == subtotal.eval sameDependencies do
    throw <| IO.userError "a store difference outside dependencies changed evaluation"

end LeanRxTest.DependencySound
