# ADR-0012: Align the PoC dogfood set with M0–M6

- Status: Accepted
- Date: 2026-08-19

## Context

The architecture's final PoC checklist named Counter, Temperature Converter,
and Dependent Tabs as the required three applications. The normative plan places
Temperature Converter in M7 and says M7 begins only after the M0–M6 PoC gate.
The latest human checkpoint instruction explicitly requires Counter, Diamond,
and Dependent Tabs for M0–M6, then requires continuation through M7–M11. These
requirements cannot all be sequenced as written.

## Alternatives considered

- Pull Temperature Converter into M6. This violates the plan's milestone order
  and duplicates the explicit human checkpoint list.
- Begin M7 before closing the PoC. This contradicts the plan's continuation gate
  and makes milestone status misleading.
- Treat any three apps as sufficient without updating the documents. This hides
  the contradiction and weakens reproducibility.

## Decision

The M0–M6 PoC dogfood set is Counter, Diamond Lab, and Dependent Tabs, matching
the explicit checkpoint instruction and already-planned milestones. Temperature
Converter remains the first M7 application. The inconsistent architecture
checklist row and dogfood sequence order change; the form requirements and M7
order remain normative.

## Consequences

M6 can close and the PoC gate can be evaluated without implementing an M7
capability early. M7 still cannot close without Temperature Converter and the
Validated Form. This ADR does not remove or weaken any browser, proof,
determinism, security, accessibility, or dogfood quality gate.

## Validation

Counter, Diamond Lab, and Dependent Tabs are generated deterministically and run
in the same Chromium gate through public APIs. STATUS records M7 as next only
after all M6 reviews and the full clean-checkout PoC suite pass.
