# ADR-0007: Publish versioned bundles through an atomic pointer

- Status: Accepted
- Date: 2026-08-19

## Context

The build contract requires generation in temporary storage followed by atomic
replacement of `dist/`. A portable POSIX rename can replace a file or symbolic
link atomically, but it cannot replace an existing nonempty directory. Moving the
old directory aside and then renaming the new directory creates an observable
gap and can strand the prior bundle if the process is interrupted.

## Decision

LeanRx generates each complete bundle in a uniquely named sibling directory.
The public output path is a relative symbolic link to that version. Publication
is one rename of a prepared symbolic link over the prior pointer, while a stable
per-output regular file lock (opened without truncation after a no-follow type
check) serializes concurrent publishers. Readers therefore resolve
the output path to either the complete old bundle or the complete new bundle;
there is no absent or partially generated public path.

The publisher retains the immediately previous bundle during cleanup and removes
older siblings only when an internal regular-file ownership marker matches the
output identity, while holding the lock. Prefix collisions and symlinks without
that positive evidence are left untouched. A failed generator or failed
pointer rename removes its private artifacts and leaves the prior pointer intact.
An absent destination bootstraps the pointer. An existing unmanaged file or real
directory fails with `LRX-PORT-003` before mutation; LeanRx does not claim that a
non-atomic legacy migration is atomic.

## Alternatives considered

- Two directory renames are rollback-friendly for caught errors but expose an
  absent-path interval and are not crash-atomic.
- Platform-specific directory-exchange syscalls would broaden the native trusted
  code and do not provide one portable implementation across CI and development.
- Replacing bundle files individually can expose mixed artifact generations.

## Consequences

Path consumers continue to use `dist/Counter.mjs` normally, but filesystem tools
that inspect without following links will observe a symbolic link. M4 build hosts
require POSIX `ln`, `readlink`, rename, and file-lock behavior. A future Windows
port needs an equally atomic pointer or exchange implementation and must fail
loudly until one exists.

## Validation

Native tests assert the output is a symbolic link, injected generation failure
preserves the old bundle, partial files never escape staging, successful rebuilds
drop stale public files, and unmanaged destinations remain untouched. They also
exercise a pre-existing managed-prefix symlink, real-directory prefix collision,
and poisoned lock symlink, checking that unrelated data remains unchanged. POSIX rename/link/locking behavior
and hostile concurrent filesystem races remain trusted platform assumptions, not
formally proved properties. Component, CLI, determinism, and Chromium gates
consume the published pointer path.
