# Accessibility guide

LeanRx treats accessibility as a typed/compiler boundary where feasible and as a
browser review obligation everywhere else. Automated axe checks are required for
dogfood applications but cannot establish complete accessibility.

## Encoded guardrails

- Click handlers on the generic view DSL are accepted only on native `button`
  elements. Click-only generic elements fail component validation.
- Button type is explicit, avoiding accidental form submission.
- Tags, attributes, and events come from closed vocabularies; an application
  cannot smuggle an unknown role/attribute through a string.
- Dynamic content uses text nodes and property/attribute setters, never raw HTML.
- Form dogfoods use typed label/control IDs, described errors, live status,
  `aria-invalid`, disabled state, and checked properties.
- Dependent Tabs uses a named native-button group with maintained exclusive
  `aria-pressed` state and keyboard activation.
- Todo row checkboxes receive title-derived accessible names, and every delegated
  action marker is attached to a native button/input.
- The Data Grid result is a named read-only table with rows/cells and
  `aria-current`, not a false interactive ARIA grid without arrow navigation.

Guardrails are intentionally conservative. If the current DSL cannot express a
semantically complete control, extend the typed capability and its tests or keep
the feature unsupported.

## Keyboard expectations

Every action must be reachable and operable through its native keyboard behavior.
Browser gates cover representative Tab/Enter flows for Counter, Tabs, forms,
Todo, the Data Grid, and the documentation site. Delegated key handlers must be
scoped to the intended typed action; Todo permanently regresses an earlier bug
where Enter on an Edit button was misrouted as edit-input Save.

Do not add `tabindex` and a click handler to a generic container as a substitute
for a native control. Composite widgets need a complete focus/arrow-key/state
contract, not only a role string.

## Dynamic content and focus

- Controlled inputs preserve the user's raw value and cursor; valid canonical
  parsing must not rewrite the actively edited field.
- Keyed regions preserve row and nested edit-input identity across reorders.
- Removing/replacing a branch disconnects its listeners and disposes owned work.
- Error state is programmatically associated with the affected control and
  updated from complete checked state rather than event history.
- Live regions are used for relevant form/effect status, but excessive live
  announcements should be reviewed manually.

## Text and injection safety

Text safety supports accessibility: hostile user strings remain visible literal
content and cannot create hidden controls, images, or event handlers. Attribute
values pass through typed safe setters. URL contexts are not exposed by the
generic DSL; when added, they will require their own scheme/context validation.

## Required dogfood review

For a new or changed application:

1. run the whole defining scenario using native keyboard actions where relevant;
2. inspect accessible names, roles, states, error associations, and source order;
3. run axe while representative dynamic content and controls are mounted;
4. test initial, valid, invalid, loading, success, failure, and disabled states;
5. test identity/focus after keyed moves and branch replacement;
6. test hostile text in every new backend/host string path;
7. dispose the component and confirm detached controls cannot update it;
8. record limitations that automated tooling cannot detect.

The browser gate is:

```sh
./scripts/check_browser.sh
```

It requires Chromium and loopback binding. A sandbox `EPERM` while opening
`127.0.0.1` is an environment restriction, not an application result; rerun in
an environment that permits the local test server.

## Current gaps

The generic view DSL now includes semantic navigation, article/aside/section,
list, and code-block elements, but it still lacks links and URL attributes,
images/alt policy, tables, broad form controls, and general keyboard events.
Specialized dogfoods implement only their checked needs. The documentation site
therefore uses a named `nav` with native page buttons and maintained
`aria-pressed` rather than pretending it has URL navigation. Screen-reader/manual
cross-platform coverage is not automated, and axe success must not be reported
as proof of accessibility.
