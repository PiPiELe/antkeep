# Project instructions

## Requirement branch base

For every session and every project, whenever a requirement/feature/fix branch is
created, base it on the current remote default branch. Fetch the remote first,
then use `origin/master` when that branch exists; otherwise use `origin/main`.
Do not create the branch from a local `master`/`main`, the current checkout, or
another feature branch. If neither remote branch is available, stop and report
the issue instead of guessing a base.

## Scope

- Android and iOS first; no WeChat mini program in the initial implementation.
- All husbandry records and media remain local. Optional online mode may use
  accounts, daily check-ins and published public content. No husbandry upload,
  cloud synchronization, analytics or ads, except explicitly selected inventory
  snapshots submitted by a signed-in user. Local features never require login.
- Read docs/PREPARATION.md before implementation.
- Prefer the smallest sufficient implementation; preserve unrelated work.
- Do not commit real husbandry records, personal photos, backups, credentials,
  signing keys, machine-specific paths or generated build artifacts.
- Distinguish source completion, automated tests, platform builds, device tests
  and store release in delivery reports.

