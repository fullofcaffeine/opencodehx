# Upstream Rebase Procedure

**Bead:** `opencodehx-050`

This procedure refreshes the upstream OpenCode oracle used by OpenCodeHX. It is a controlled oracle update, not a source merge from OpenCode into this repo.

## Scope

- `../opencode` remains the read-only upstream behavioral oracle.
- OpenCodeHX source stays Haxe-authored; do not copy broad upstream TypeScript into `src/opencodehx`.
- Update the upstream pin and generated parity matrices in the same change.
- Turn every behavior drift, new test, removed test, and changed fixture expectation into either updated OpenCodeHX evidence or a Bead.

## Prerequisites

Use the current Beads workflow from `bd onboard` / `bd prime`. This checkout was documented with `bd version 1.0.4`.

```sh
bd ready --json
bd show opencodehx-050 --json
bd update opencodehx-050 --claim --json
```

Before touching the upstream checkout, make sure both worktrees are clean:

```sh
git status --short
git -C ../opencode status --short
```

If `../opencode` has tracked local changes, stop and resolve that outside this procedure. Untracked local artifacts may be ignored only when they are already documented in `reference/upstream-opencode.pin.json`.

## Refresh Snapshot

Fetch the upstream OpenCode remote and select the exact commit to use as the new oracle:

```sh
git -C ../opencode fetch origin dev
git -C ../opencode rev-parse origin/dev
git -C ../opencode log -1 --format='%H%n%cI%n%s' origin/dev
```

Then move only the sibling oracle checkout:

```sh
git -C ../opencode checkout dev
git -C ../opencode reset --hard <new-upstream-commit>
```

Record the new snapshot in `reference/upstream-opencode.pin.json`:

- `recorded_at`
- `checkout.commit`
- `checkout.commit_date`
- `checkout.commit_subject`
- `checkout.branch_state`
- `checkout.dirty_state`
- `package.version`
- `inventory.source_files`
- `inventory.test_files`
- `inventory.approx_source_loc`

Update `docs/upstream-opencode-oracle.md` with the same human-readable values. Keep the reference commands current with upstream's package scripts.

## Regenerate Matrices

Regenerate the source and test inventories from the refreshed checkout:

```sh
npm run inventory:matrix
```

Review the matrix diff instead of accepting it blindly:

```sh
git diff -- reference/opencode-source-parity-matrix.csv
git diff -- reference/opencode-test-priority-matrix.csv
git diff -- reference/opencode-test-port-matrix.csv
git diff -- docs/opencode-source-inventory.md docs/opencode-test-port-matrix.md
```

The generated matrices are expected to change when upstream adds, removes, renames, or moves tests. The review target is whether each changed row still has an accurate area, runtime class, priority, status, evidence, defer reason, replacement fixture, and `next_bead`.

## Update Evidence

For each upstream change, classify it before editing OpenCodeHX:

- Existing behavior still matches: update matrix evidence or docs only.
- Existing behavior changed: update the Haxe implementation and the focused smoke/golden fixture in the owning slice.
- New upstream test maps to an active slice: add a Haxe-owned fixture, generated target test, or differential harness evidence.
- New upstream test is outside current scope: leave the row `deferred` or `partial`, but assign a concrete `next_bead` and write a specific defer reason.
- Upstream removed or renamed a test: update the generated matrix and remove stale replacement evidence only after confirming the behavior is no longer an oracle input elsewhere.

Do not mark a row `ported` just because OpenCodeHX compiles. A row needs executable evidence or a documented golden/differential fixture.

## Create Drift Beads

Create Beads for drift that cannot be resolved in the refresh change. Keep them precise enough for the next agent to act without replaying the whole diff:

```sh
bd create \
  --title="Port upstream <area> drift from <old-short> to <new-short>" \
  --description="[discovered-from: opencodehx-050]

Upstream changed <files/tests>. OpenCodeHX currently has <existing evidence>. Missing scope: <specific behavior>." \
  --type=task \
  --priority=2 \
  --acceptance="Updated Haxe-owned fixture or documented deferral covers the changed upstream behavior; npm run inventory:matrix and relevant smokes pass."
```

If drift exposes a `genes-ts` compiler issue, create the paired compiler Bead from `../genes` and keep the OpenCodeHX Bead focused on the blocked product slice.

After creating or updating Beads, export the JSONL source of truth:

```sh
bd export -o .beads/issues.jsonl
bd dolt push
```

If this checkout has no Dolt remote, `bd dolt push` may skip; still run it so the absence is explicit.

## Gates

At minimum, a refresh-only change must pass:

```sh
npm run inventory:matrix
npm run public:precommit
git diff --check
```

If any implementation, fixture, generated resource, or command behavior changes, also run the relevant focused smoke and then the broad gate:

```sh
npm run build
npm run smoke
```

Run upstream commands from the package root only when the refresh needs direct upstream evidence:

```sh
cd ../opencode/packages/opencode
bun run typecheck
bun test --timeout 30000
bun run test:ci
bun run build
```

Record any skipped upstream command and the reason in the Bead close message.

## Closeout

Before closing the Bead or refresh task:

1. Confirm `reference/upstream-opencode.pin.json` and `docs/upstream-opencode-oracle.md` agree.
2. Confirm generated matrix docs and CSV files are regenerated.
3. Confirm every matrix `partial` or `deferred` executable test row has a reason, replacement fixture, and `next_bead`.
4. Confirm all unresolved drift has a Bead.
5. Run `bd export -o .beads/issues.jsonl` and `bd dolt push`.
6. Commit and push the OpenCodeHX changes.
