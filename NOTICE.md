# Notices and provenance

LeanRx is a greenfield implementation. As of 2026-08-21, no source code has been
copied or adapted from Qed or another third-party project.

Qed is documented as prior art in `docs/prior-art/qed.md`. Its repository is
MIT-licensed, but that license does not apply to this repository merely because
the project was studied. If code is later copied or adapted, this file and the
affected source comments must record the upstream URL, revision, license,
modified files, and nature of the adaptation before that code is committed.

No license has yet been selected for LeanRx itself.

Browser acceptance tests use the following development-only packages; no
package source is copied into LeanRx:

- `@playwright/test` 1.62.1 and Playwright/Chromium test tooling,
  Apache-2.0;
- `@axe-core/playwright` 4.13.0 and `axe-core` 4.13.0, MPL-2.0.

Exact dependency integrity and transitive versions are recorded in
`pnpm-lock.yaml`. They are test infrastructure and are not imported by generated
LeanRx application modules or the browser host.

The documentation build imports MD4Lean at revision
`31907cc18f48a95384f99cee5582c00fb39e0f67`, Copyright © 2024 Jz Pan, under the
MIT License. MD4Lean vendors a custom MD4C fork, Copyright © 2016–2024 Martin
Mitáš, also under the MIT License. These sources remain in Lake's dependency
checkout rather than being copied into LeanRx. MD4Lean/MD4C parse documentation
at native build time; generated browser modules do not import either library.
Their complete license texts are distributed in the corresponding dependency
checkout and upstream repositories, with the exact MD4Lean revision recorded in
`lake-manifest.json`.
