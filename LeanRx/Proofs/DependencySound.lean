import LeanRx.Core.Expr

namespace LeanRx.RxExpr

/-- Expression evaluation can observe only the fields in its dependency index. -/
theorem eval_congr_on_deps {Γ : Schema} {deps : DepSet Γ} {α : Type}
    (expr : RxExpr Γ deps α) (left right : Store Γ)
    (agree : Store.AgreeOn deps left right) :
    expr.eval left = expr.eval right := by
  induction expr generalizing left right with
  | literal value =>
      simp only [eval]
  | readWith _ field =>
      simpa only [eval] using agree field (DepSet.contains_singleton field)
  | unary op value ih =>
      simp only [eval]
      exact congrArg op.eval <| ih left right agree
  | binary op first second firstIH secondIH =>
      simp only [eval]
      have firstEqual : first.eval left = first.eval right :=
        firstIH left right <| Store.agreeOn_union_left left right _ _ agree
      have secondEqual : second.eval left = second.eval right :=
        secondIH left right <| Store.agreeOn_union_right left right _ _ agree
      calc
        op.eval (first.eval left) (second.eval left) =
            op.eval (first.eval right) (second.eval left) :=
          congrArg (fun value => op.eval value (second.eval left)) <|
            firstEqual
        _ = op.eval (first.eval right) (second.eval right) :=
          congrArg (op.eval (first.eval right)) secondEqual
  | ifThenElse condition yes no conditionIH yesIH noIH =>
      simp only [eval]
      have conditionEqual : condition.eval left = condition.eval right :=
        conditionIH left right <| Store.agreeOn_union_left left right _ _ agree
      have branchesAgree : Store.AgreeOn
          (DepSet.union yes.dependencies no.dependencies) left right :=
        Store.agreeOn_union_right left right _ _ agree
      have yesEqual : yes.eval left = yes.eval right :=
        yesIH left right <| Store.agreeOn_union_left left right _ _ branchesAgree
      have noEqual : no.eval left = no.eval right :=
        noIH left right <| Store.agreeOn_union_right left right _ _ branchesAgree
      rw [conditionEqual]
      split
      · exact yesEqual
      · exact noEqual
  | vectorGetWith _ values index valuesIH indexIH =>
      simp only [eval]
      have valuesEqual : values.eval left = values.eval right :=
        valuesIH left right <| Store.agreeOn_union_left left right _ _ agree
      have indexEqual : index.eval left = index.eval right :=
        indexIH left right <| Store.agreeOn_union_right left right _ _ agree
      rw [valuesEqual, indexEqual]

end LeanRx.RxExpr
