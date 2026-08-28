#!/usr/bin/env bash
set -euo pipefail

fixtures=(
  Test/fixtures/compile-fail/ForgeDepSet.lean
  Test/fixtures/compile-fail/UnsupportedRead.lean
  Test/fixtures/compile-fail/MisrepresentInt.lean
  Test/fixtures/compile-fail/ForgePlannedGraph.lean
  Test/fixtures/compile-fail/MutationInDerived.lean
  Test/fixtures/compile-fail/MissingRuntimeEq.lean
  Test/fixtures/compile-fail/UnsupportedViewExpr.lean
  Test/fixtures/compile-fail/UnknownEventAttribute.lean
  Test/fixtures/compile-fail/RawHtmlView.lean
  Test/fixtures/compile-fail/ClickOnlyDiv.lean
  Test/fixtures/compile-fail/UnknownEventBinding.lean
  Test/fixtures/compile-fail/DerivedReadInEvent.lean
  Test/fixtures/compile-fail/RecursiveEventDispatch.lean
  Test/fixtures/compile-fail/ComponentRoleMismatch.lean
  Test/fixtures/compile-fail/ComponentCycle.lean
  Test/fixtures/compile-fail/TabsLengthMismatch.lean
  Test/fixtures/compile-fail/EmptyTabs.lean
  Test/fixtures/compile-fail/InvalidFinLiteral.lean
  Test/fixtures/compile-fail/NatVectorIndex.lean
  Test/fixtures/compile-fail/SubmitRawForm.lean
  Test/fixtures/compile-fail/ForgeSubmitCommand.lean
  Test/fixtures/compile-fail/ForgeStateControlBinding.lean
  Test/fixtures/compile-fail/ForgeTemperatureUpdate.lean
  Test/fixtures/compile-fail/ForgeKeyedList.lean
  Test/fixtures/compile-fail/ForgeConditionalResult.lean
  Test/fixtures/compile-fail/ForgePositionalResult.lean
  Test/fixtures/compile-fail/ForgeRegionResult.lean
  Test/fixtures/compile-fail/ForgeTodoState.lean
  Test/fixtures/compile-fail/ForgeForeignPort.lean
  Test/fixtures/compile-fail/MismatchedStructuredPort.lean
  Test/fixtures/compile-fail/ForgeNotesState.lean
  Test/fixtures/compile-fail/ForgeIssueBrowserState.lean
  Test/fixtures/compile-fail/ForgeGridSpec.lean
  Test/fixtures/compile-fail/ForgePlannedDeltas.lean
  Test/fixtures/compile-fail/ForgeGridChecked.lean
  Test/fixtures/compile-fail/ForgeGridState.lean
  Test/fixtures/compile-fail/CustomGridCostModel.lean
  Test/fixtures/compile-fail/UnstageableRxAtom.lean
  Test/fixtures/compile-fail/UnsupportedTag.lean
  Test/fixtures/compile-fail/KeyedListInTypedView.lean
  Test/fixtures/compile-fail/DynamicAttrInTypedView.lean
  Test/fixtures/compile-fail/EventInLogicalView.lean
  Test/fixtures/compile-fail/TypedEventOnButton.lean
  Test/fixtures/compile-fail/UnknownTypedEventBinding.lean
  Test/fixtures/compile-fail/MalformedEventStep.lean
  Test/fixtures/compile-fail/UnsupportedStateLiteral.lean
  Test/fixtures/compile-fail/TypedEventIgnoresPayload.lean
  Test/fixtures/compile-fail/PayloadClassMismatch.lean
  Test/fixtures/compile-fail/SubmitOnButton.lean
  Test/fixtures/compile-fail/ReflectOnParagraph.lean
  Test/fixtures/compile-fail/CheckboxTypeOnButton.lean
  Test/fixtures/compile-fail/IntTypedEventPayload.lean
  Test/fixtures/compile-fail/RegionButtonAsCell.lean
  Test/fixtures/compile-fail/RegionUnknownRowField.lean
  Test/fixtures/compile-fail/IntImmutableProp.lean
  Test/fixtures/compile-fail/ChildPropMismatch.lean
  Test/fixtures/compile-fail/RowUpdateUnknownField.lean
  Test/fixtures/compile-fail/RowClassSelectDynamic.lean
  Test/fixtures/compile-fail/AttrSelectOnParagraph.lean
  Test/fixtures/compile-fail/RowTypedPayloadOnClick.lean
  Test/fixtures/compile-fail/IntRowPayload.lean
  Test/fixtures/compile-fail/BranchInTypedView.lean
  Test/fixtures/compile-fail/RowBranchUnknownField.lean
  Test/fixtures/compile-fail/RowBranchOneSidedClick.lean
  Test/fixtures/compile-fail/RowReflectOnSpan.lean
  Test/fixtures/compile-fail/RowAutoFocusOnSpan.lean
  Test/fixtures/compile-fail/RowAutoFocusOutsideBranch.lean
  Test/fixtures/compile-fail/AutoFocusInTypedView.lean
  Test/fixtures/compile-fail/RowBranchOneSidedDblClick.lean
  Test/fixtures/compile-fail/RowChangeOnTextInput.lean
  Test/fixtures/compile-fail/RowCheckedReflectOnTextInput.lean
  Test/fixtures/compile-fail/BroadcastUnknownRowField.lean
  Test/fixtures/compile-fail/RemoveIfUnknownRegion.lean
  Test/fixtures/compile-fail/CountUnknownRegion.lean
  Test/fixtures/compile-fail/FilterUnknownRegion.lean
  Test/fixtures/compile-fail/FilterUnknownRowField.lean
  Test/fixtures/compile-fail/FilterDuplicateLiteral.lean
  Test/fixtures/compile-fail/KeyBranchOutsideSealedSet.lean
  Test/fixtures/compile-fail/KeyBranchWithoutPayload.lean
  Test/fixtures/compile-fail/KeyBranchMixedSteps.lean
  Test/fixtures/compile-fail/RowGuardMixedSteps.lean
  Test/fixtures/compile-fail/RowGuardOnTypedEvent.lean
  Test/fixtures/compile-fail/RowGuardKeepsRow.lean
  Test/fixtures/compile-fail/RowGuardUnknownField.lean
  Test/fixtures/compile-fail/RowTrimGuardSubject.lean
  Test/fixtures/compile-fail/RowTrimUnknownField.lean
  Test/fixtures/compile-fail/EventGuardLiteral.lean
  Test/fixtures/compile-fail/EventGuardHitStep.lean
  Test/fixtures/compile-fail/KeyEventPayloadRef.lean
  Test/fixtures/compile-fail/KeyEventMixedSteps.lean
  Test/fixtures/compile-fail/AttrSelectNonTrimHead.lean
  Test/fixtures/compile-fail/AttrSelectNegatedPredicate.lean
  Test/fixtures/compile-fail/HiddenThresholdLiteral.lean
  Test/fixtures/compile-fail/HiddenPredicateThreshold.lean
  Test/fixtures/compile-fail/HiddenPredicateUnknownField.lean
  Test/fixtures/compile-fail/CheckedPredicateThreshold.lean
  Test/fixtures/compile-fail/CheckedPredicateUnknownField.lean
  Test/fixtures/compile-fail/CheckedOnNonCheckbox.lean
  Test/fixtures/compile-fail/BroadcastPayloadString.lean
  Test/fixtures/compile-fail/BroadcastPayloadComposed.lean
  Test/fixtures/compile-fail/BroadcastPayloadUnknownField.lean
  Test/fixtures/compile-fail/CountLabelThreshold.lean
  Test/fixtures/compile-fail/CountLabelDynamicBranch.lean
)
fragments=(
  "Constructor for"
  "LeanRx.RuntimeRep HostOnly"
  "LeanRx.RuntimeType Int"
  'constructor for `LeanRx.PlannedGraph` is marked as private'
  "LeanRx.Update S"
  "LeanRx.RuntimeEq Int"
  "@LeanRx.View.scalarText"
  "error[LRX-VIEW-008]"
  "error[LRX-VIEW-010]"
  "error[LRX-VIEW-005]"
  "error[LRX-VIEW-006]"
  "error[LRX-TYPE-108]"
  "error[LRX-ELAB-107]"
  "error[LRX-ELAB-103]"
  "error[LRX-GRAPH-001]"
  "Vector String (1 + 1)"
  "Vector String (0 + 1)"
  "Tactic \`decide\` proved"
  "(Fin 3)"
  "ValidatedForm"
  'Constructor for `LeanRx.Form.FakeSubmitCommand` is marked as private'
  'Constructor for `LeanRx.Form.StateControlBinding` is marked as private'
  'Constructor for `LeanRx.Form.TemperatureSpec.UpdatePlan` is marked as private'
  'Constructor for `LeanRx.Region.KeyedList` is marked as private'
  'constructor for `ConditionalResult` is marked as private'
  'constructor for `PositionalResult` is marked as private'
  'constructor for `KeyedResult` is marked as private'
  'Constructor for `LeanRx.Todo.State` is marked as private'
  'constructor for `ForeignPort` is marked as private'
  "Application type mismatch"
  'constructor for `State` is marked as private'
  'constructor for `State` is marked as private'
  'Constructor for `LeanRx.Grid.Spec` is marked as private'
  'Constructor for `LeanRx.Collection.PlannedDeltas` is marked as private'
  'Constructor for `LeanRx.Grid.Spec.Checked` is marked as private'
  'Constructor for `LeanRx.Grid.State` is marked as private'
  'Invalid argument name `costModel`'
  "error[LRX-RX-001]"
  "error[LRX-VIEW-007]"
  "error[LRX-VIEW-011]"
  "error[LRX-VIEW-012]"
  "error[LRX-VIEW-013]"
  "error[LRX-VIEW-016]"
  "error[LRX-VIEW-017]"
  "error[LRX-ELAB-104]"
  "error[LRX-ELAB-105]"
  "error[LRX-ELAB-108]"
  "error[LRX-VIEW-018]"
  "error[LRX-VIEW-019]"
  "error[LRX-VIEW-020]"
  "error[LRX-VIEW-022]"
  "error[LRX-ELAB-109]"
  "error[LRX-VIEW-027]"
  "error[LRX-ELAB-114]"
  "error[LRX-ELAB-113]"
  "error[LRX-ELAB-112]"
  "error[LRX-ELAB-115]"
  "error[LRX-ELAB-116]"
  "error[LRX-VIEW-032]"
  "error[LRX-VIEW-033]"
  "error[LRX-ELAB-117]"
  "error[LRX-VIEW-034]"
  "error[LRX-ELAB-118]"
  "error[LRX-VIEW-034]"
  "error[LRX-VIEW-035]"
  "error[LRX-VIEW-036]"
  "error[LRX-VIEW-036]"
  "error[LRX-VIEW-036]"
  "error[LRX-VIEW-034]"
  "error[LRX-VIEW-037]"
  "error[LRX-VIEW-037]"
  "error[LRX-ELAB-115]"
  "error[LRX-ELAB-119]"
  "error[LRX-ELAB-119]"
  "error[LRX-ELAB-120]"
  "error[LRX-ELAB-120]"
  "error[LRX-TYPE-113]"
  "error[LRX-VIEW-039]"
  "error[LRX-ELAB-121]"
  "error[LRX-ELAB-121]"
  "error[LRX-ELAB-122]"
  "error[LRX-ELAB-122]"
  "error[LRX-ELAB-122]"
  "error[LRX-ELAB-122]"
  "error[LRX-ELAB-122]"
  "error[LRX-ELAB-115]"
  "error[LRX-ELAB-123]"
  "error[LRX-ELAB-123]"
  "error[LRX-ELAB-124]"
  "error[LRX-ELAB-124]"
  "error[LRX-VIEW-012]"
  "error[LRX-VIEW-012]"
  "error[LRX-ELAB-125]"
  "error[LRX-ELAB-125]"
  "error[LRX-ELAB-119]"
  "error[LRX-ELAB-125]"
  "error[LRX-ELAB-119]"
  "error[LRX-VIEW-043]"
  "error[LRX-ELAB-126]"
  "error[LRX-ELAB-126]"
  "error[LRX-ELAB-115]"
  "error[LRX-ELAB-127]"
  "error[LRX-ELAB-127]"
)

for index in "${!fixtures[@]}"; do
  fixture="${fixtures[$index]}"
  if output="$(lake env lean -E hasSorry "$fixture" 2>&1)"; then
    echo "compile-fail fixture unexpectedly succeeded: $fixture" >&2
    exit 1
  fi
  if [[ "$output" != *"${fragments[$index]}"* ]]; then
    echo "compile-fail fixture produced the wrong diagnostic: $fixture" >&2
    echo "$output" >&2
    exit 1
  fi
done

cycle_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/ComponentCycle.lean 2>&1 || true)"
if [[ "$cycle_output" != *"a → b → a"* || "$cycle_output" != *"ComponentCycle.lean:"* ]]; then
  echo "component cycle diagnostic lost its path or source locations" >&2
  echo "$cycle_output" >&2
  exit 1
fi

binding_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/UnknownEventBinding.lean 2>&1 || true)"
if [[ "$binding_output" != *"UnknownEventBinding.lean:"* ]]; then
  echo "unknown event diagnostic lost its JSX attribute location" >&2
  echo "$binding_output" >&2
  exit 1
fi

click_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/ClickOnlyDiv.lean 2>&1 || true)"
if [[ "$click_output" != *"ClickOnlyDiv.lean:10:"* ]]; then
  echo "root JSX diagnostic lost its original element location" >&2
  echo "$click_output" >&2
  exit 1
fi

derived_read_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/DerivedReadInEvent.lean 2>&1 || true)"
if [[ "$derived_read_output" != *"derived reads require a transaction barrier"* ]]; then
  echo "derived event read diagnostic lost its future-capability guidance" >&2
  echo "$derived_read_output" >&2
  exit 1
fi

echo "compile-fail type-contract fixtures passed"
