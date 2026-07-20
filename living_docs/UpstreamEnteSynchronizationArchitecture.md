# Upstream Ente Synchronization Architecture

**Status:** As-built recurring maintenance architecture, verified 2026-07-20

This document defines how the fork absorbs official Ente changes without
losing the configurable self-hosted mobile applications or rewriting published
history. It is the maintenance runbook for source integration. Building and
distributing a release remain separate workflows.

Related documents:

- [Canonical operator runbook](../UPSTREAM_SYNC.md)
- [Self-hosted mobile documentation index](../mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md)
- [Configurable-server architecture](ConfigurableSelfHostedMobileServerArchitecture.md)
- [Upstream synchronization implementation record](UpstreamEnteSynchronization.md)
- [Mobile build guide](../mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md)

## 1. Invariants

Every synchronization must preserve all of these properties:

- Official Ente history and the fork's published history remain reachable.
- `origin` is the personal fork and the only push destination. `upstream` is
  the official Ente repository and has a disabled push URL.
- Fork `main` remains the last accepted state while integration happens on a
  dated `sync/upstream-YYYY-MM-DD` branch.
- Android keeps release package `me.vanton.ente.photos.selfhosted` and the
  normal debug `.debug` suffix.
- iOS keeps bundle `me.vanton.ente.photos.selfhosted` on the core-only
  `SelfHostedRunner` target and shared `selfhosted` scheme.
- Both guarded wrappers own their target/flavor and compile one validated
  configurable HTTPS Museum default. Stored runtime bindings, logout-before-
  switching behavior, and same-origin authenticated networking remain intact.
- Synchronization does not publish, install, sign a release, change Apple or
  Firebase state, alter a private server, or advance a release ledger.

## 2. Remote and branch model

```text
official history                         fork history
upstream/main                            origin/main
      \                                     /
       \                                   /
        +-- sync/upstream-YYYY-MM-DD ------+
                    merge commit
                         |
              repairs and validation
                         |
                 owner review / PR
                         |
                 fork main, later
```

Verify the remote boundary before fetching:

```sh
git remote -v
git remote get-url origin
git remote get-url upstream
git remote get-url --push upstream
```

The upstream push URL must be a disabled sentinel, not the official GitHub
URL. Establish that boundary once if necessary:

```sh
git remote set-url --push upstream DISABLED
```

Never merge a moving reference without recording it. Fetch first, then capture
the exact commits and divergence:

```sh
git fetch upstream main

fork_sha="$(git rev-parse origin/main)"
official_sha="$(git rev-parse upstream/main)"
merge_base="$(git merge-base "$fork_sha" "$official_sha")"

git rev-list --left-right --count "$fork_sha...$official_sha"
printf '%s\n' "$fork_sha" "$official_sha" "$merge_base"
```

Start only from a clean, pushed fork `main` that exactly matches the intended
`origin/main`:

```sh
git switch main
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
git switch -c "sync/upstream-$(date +%F)"
```

If local `main` is not the intended `origin/main`, resolve that discrepancy
explicitly before creating the integration branch. Do not reset, rebase, or
force-push merely to make the check pass.

## 3. Merge sequence

Merge the recorded official commit with both histories intact:

```sh
git merge --no-ff --no-commit "$official_sha"
git status --short
git diff --name-only --diff-filter=U
```

Review every textual conflict and every important file changed on both sides.
An automatically merged file is not automatically semantically correct.
Resolve the complete merge atomically, scan for markers, and create a dedicated
merge commit before compatibility repairs:

```sh
git diff --check
git grep -n -E '^(<<<<<<< |>>>>>>> )'
git commit -m "Merge official Ente main at $official_sha"
```

Do not use repository-wide `ours` or `theirs`. It can silently discard either
official security/compatibility changes or the fork's endpoint, identity, and
distribution controls.

### Conflict ownership

| Surface | Default owner | Required reconciliation |
|---|---|---|
| Shared packages, toolchain pins, CI, upstream app features, and upstream deletions | Upstream | Keep the new upstream structure and adapt fork code to its APIs. Do not resurrect removed files without a proven dependency. |
| Android package/flavor, iOS bundle/target/scheme, empty self-hosted entitlements | Fork | Preserve the separate application identities and core-only graphs while adopting upstream SDK and platform floors. |
| Endpoint policy, stored binding, startup fail-closed behavior, switch/logout UX, and origin constraints | Fork behavior on upstream APIs | Preserve the behavioral contracts; refactor only as required by upstream interfaces. |
| Flutter/Dart/Rust dependency locks and CocoaPods lock/project references | Generated combined state | Resolve the merge to a valid seed, then regenerate with exact current tools and prove a second generation is clean. |
| Signing, preparation, publication, receipts, and fixed tester groups | Fork | Preserve guards and immutable evidence contracts. Never introduce private signing or Firebase values. |
| Documentation | Combined current truth | Keep historical evidence historical; update canonical runbooks only for current commands, versions, platform floors, and boundaries. |

## 4. Dependency and generation gate

Derive tool versions from the merged repository and lockfiles rather than
assuming the previous sync's versions. Initialize committed submodules before
analysis:

```sh
git submodule update --init --recursive
```

For the verified 2026-07-20 baseline, the relevant tools were Flutter 3.38.10
with Dart 3.10.9, rustup-managed Rust/Cargo 1.97, CocoaPods 1.17.0, and JDK 17.
Use the exact current equivalents on later synchronizations.

From `mobile/`, restore the locked workspace:

```sh
"$FLUTTER_BIN" pub get --enforce-lockfile
```

Put rustup's proxies first and regenerate Flutter/Rust bindings from `rust/`:

```sh
export PATH="$HOME/.cargo/bin:$PATH"
cargo codegen frb
git status --short
cargo codegen frb
git status --short
```

The second run must be byte-stable. If an escalated or non-interactive shell
selects another `cargo` or `rustc`, make both executable paths explicit before
changing source.

On macOS, use the CocoaPods version recorded in the merged Photos lockfile:

```sh
cd mobile/apps/photos/ios
pod install
pod install --deployment
```

The deployment-mode run must report no lock changes. Compare every fork-only
iOS configuration with the new Podfile and upstream target deployment floor;
those values often merge without a textual conflict. Likewise derive Android
JDK, SDK, NDK, and ABI requirements from the merged Gradle source before
editing compatibility code.

## 5. Runtime and platform gates

Validation proceeds from inexpensive semantic checks to platform builds:

```text
ancestry and conflict audit
        |
dependency and generated-output stability
        |
endpoint tests in standard, configurable, and locked modes
        |
Android/iOS contract and publication tests
        |
format and full mobile analysis
        |
guarded Android debug and iOS Simulator builds
        |
documentation, privacy, and final diff audit
```

Use a public non-operational origin for every synchronization build:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://photos.example.com"
```

At minimum, test:

- endpoint parsing and canonicalization;
- fail-closed configuration startup;
- stored-binding upgrade behavior;
- anonymous, credential-free, no-redirect server validation;
- mutation-free validation failures;
- local logout completing before a new origin is activated;
- same-origin authenticated Museum requests;
- Android flavor/package, SDK, ABI, signing, preparation, and publication
  contracts; and
- iOS target/bundle, core-only graph, deployment target, Ad Hoc preparation,
  and publication contracts.

Run the focused tests under the standard compilation and again with the real
configurable and locked Dart defines. Then run tracked-source formatting and
full workspace analysis with the pinned SDK. The exact file list can evolve;
the behavioral categories above may not be silently dropped.

The quarantine build boundary is:

```sh
cd mobile/apps/photos
./scripts/build_self_hosted_android.sh --debug
./scripts/build_self_hosted_ios.sh --simulator
```

Audit the Android debug APK for package, version, SDKs, ABIs, debug state,
compiled example endpoint, ZIP integrity, alignment, signature scheme, size,
and SHA-256. Audit the Simulator `.app` for bundle/version, minimum iOS,
arm64 binaries, compiled endpoint, absence of extensions and provisioning
profiles, empty entitlements, ad-hoc signature validity, size, and hashes.
Do not install either artifact as part of synchronization.

## 6. Final integration audit

Before review, prove both source histories, a clean diff, and the remote
boundary:

```sh
git merge-base --is-ancestor upstream/main HEAD
git merge-base --is-ancestor origin/main HEAD
git rev-list --left-right --count upstream/main...HEAD
git diff --check upstream/main..HEAD
git grep -n -E '^(<<<<<<< |>>>>>>> )'
git submodule status --recursive
git remote -v
git status --short --branch
```

The left divergence count must be zero for the recorded upstream commit. The
working tree must be clean, all required submodules initialized at their
recorded SHAs, and upstream push disabled. Review the complete
`upstream/main..HEAD` inventory: expected fork-only runtime, platform, tests,
scripts, documentation, and task records should explain every changed file.

Run a private-value scan over changed documentation and scripts. Real server
origins, object-storage routes, tester identities, Firebase project/App IDs,
Apple Team/device/profile data, credentials, artifacts, and receipts must not
enter Git. Public placeholder origins and application identities are expected.

## 7. Source integration is not a release

Passing every gate means only that the sync branch is ready for owner review.
It does not authorize any of the following:

- pushing the branch or merging it into fork `main`;
- preparing or publishing a signed Android or iOS release;
- incrementing Firebase build ledgers or notifying testers;
- registering Apple devices, refreshing profiles, or changing certificates;
- installing on a physical device; or
- upgrading or reconfiguring Museum, object storage, DNS, TLS, or Tailscale.

After owner review, the branch may be pushed and merged through the fork's
normal review path. A later release starts from that accepted, pushed commit,
uses higher platform build numbers, private signing inputs, live server health
checks, immutable preparation, and the applicable Firebase operations guide.

## 8. Failure recovery

| Failure point | Safe recovery |
|---|---|
| Before the merge commit | Inspect first; if the selected upstream or scope is wrong, use `git merge --abort` and keep fork `main` untouched. |
| After the merge commit, before review | Preserve useful evidence if needed, then abandon the integration branch and start a new dated branch from the accepted fork `main`. |
| Generated output is unstable | Stop, verify exact Flutter/Dart/Rust/CocoaPods paths and submodules, and rerun. Do not hand-edit generated files merely to hide drift. |
| A custom target no longer fits upstream architecture | Stop at the relevant task. Record the conflicting invariants and obtain an explicit design decision before broadening scope. |
| Platform build fails only with the workstation's default tool | Reproduce the merged repository's CI/toolchain contract first. Do not downgrade source or dependencies to accommodate an unrelated global installation. |
| External release action was accidentally started | Stop source synchronization. Preserve the external attempt evidence and follow the platform distribution recovery runbook; do not retry blindly. |

Never rewrite published history, force-push, or destructively reset the working
fork to recover a synchronization branch.

## 9. Maintenance checklist

For each future catch-up:

1. Confirm fork `main` is clean, pushed, and currently releasable.
2. Verify remote URLs and the disabled upstream push URL.
3. Fetch official `main`; record fork, official, merge-base, and divergence
   SHAs in a new living record.
4. Create a dated integration branch and merge the exact official commit with
   `--no-ff`.
5. Resolve conflicts by ownership; audit semantically important automatic
   merges and upstream deletions.
6. Restore submodules, locked dependencies, Rust bindings, pods, and other
   generated sources with exact merged tool versions; prove repeatability.
7. Run endpoint tests in all modes, platform contract tests, formatting, and
   full mobile analysis.
8. Build and audit only the guarded Android debug and iOS Simulator artifacts
   against a public example endpoint.
9. Update canonical documents for current source/toolchain/platform facts
   while leaving historical release evidence intact.
10. Prove ancestry, zero upstream-behind count, clean diff/status, disabled
    upstream push, valid links/scripts, and privacy boundaries.
11. Commit each task boundary, review the complete branch, and request explicit
    approval before any push, fork-main merge, physical-device action, private
    server change, or distribution workflow.

## 10. Evidence from the first full synchronization

The 2026-07-20 execution integrated fork commit `ed63fc138d88d9855e1ad1c10cea50747d5d0c0b`
with official commit `e184e77116dbffd825b755c0fb2e4b924f837569`
from merge base `dda1d1f790e2d9a7bd68b0cf84a7c97efb4f5374`.
Its 1,014 upstream-only commits produced one textual conflict, the generated
Photos iOS lockfile. Semantic audits additionally found two stale removed
framework references and an upstream iOS floor increase that fork-only Xcode
configurations had not inherited.

The run also established four recurring operational lessons:

- initialize recursive submodules before treating missing assets as source
  regressions;
- make rustup `cargo` and `rustc` selection explicit in non-interactive shells;
- satisfy plugin-level Java toolchains, not just the Gradle launcher; and
- distinguish a successful source build from the older releases that remain
  installed and distributed.

With those repairs, dependency generation was stable, full mobile analysis had
no issues, all focused self-hosted tests passed, and both guarded platform
builds passed their artifact audits without external mutation.
