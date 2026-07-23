# TestFlight iOS Distribution for the Self-Hosted Photos App

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-23
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** [iOS distribution runbook](../mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md), planned `living_docs/TestFlightIOSDistributionArchitecture.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title                                                                               | Size | Status         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ----: | ---: | ----------------------------------------------------------------------------------- | :--: | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|     1 |  1.1 | Audit App Store Connect and TestFlight prerequisites without changing them          |  S   | 🟢 done        | Completed a read-only repository, local-tooling, and owner-guided account audit. The Ente team can create apps, has clear agreements, and has App Store Connect API access. Bundle `me.vanton.ente.photos.selfhosted` has no app record, so it also has no TestFlight groups, beta metadata, builds, or export-compliance state. Xcode 26.6 supplies official upload tools, but the current shell sees no valid signing identity or matching App Store profile. App Manager is the least role for the selected external-testing pipeline. The unrelated exposed `.p8` key is excluded and must be rotated by its owning team. No Apple state changed. |
|     1 |  1.2 | Establish the App Store Connect app record and App Store signing assets             |  M   | ⚪ not started | Create the iOS app record manually for `me.vanton.ente.photos.selfhosted`, resolve the missing local Apple Distribution identity, create a manual App Store provisioning profile for the core-only target, and generate a dedicated App Manager API key stored outside Git with owner-only permissions. Record only non-secret identifiers and public certificate evidence.                                                                                                                                                                                                                                                                           |
|     1 |  1.3 | Add an App Store distribution export mode while retaining Ad Hoc fallback           |  M   | ⚪ not started | Extend the guarded iOS builder for App Store signing and export. Keep the proven Ad Hoc path intact until external TestFlight acceptance completes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
|     1 |  1.4 | Prepare and audit an immutable TestFlight IPA and manifest                          |  M   | ⚪ not started | Reuse the isolated pushed-source build model, but bind the output to App Store signing, the configurable endpoint policy, the review Museum origin, and TestFlight-specific identity checks without contacting Apple services.                                                                                                                                                                                                                                                                                                                                                                                                                        |
|     2 |  2.1 | Add App Store Connect JWT authentication and read-only preflight                    |  M   | ⚪ not started | Load the issuer, key identifier, and private-key path from private operator configuration; validate the exact app, group, permissions, agreements, metadata, version, and build before any mutation.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|     2 |  2.2 | Add exact confirmation, one-shot upload, and partial-attempt evidence               |  M   | ⚪ not started | Re-audit immutable inputs after `PUBLISH <release-id>`, invoke one official Apple upload path, and preserve a secret-free attempt record whenever upload outcome is incomplete or ambiguous.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
|     2 |  2.3 | Add resumable processing, group assignment, review submission, and success receipts |  M   | ⚪ not started | Resume from Apple build state after upload, validate the processed build, assign it to the pre-existing external group, submit Beta App Review, and record every transition without keeping one command open indefinitely.                                                                                                                                                                                                                                                                                                                                                                                                                            |
|     2 |  2.4 | Reconcile an existing Apple upload without uploading again                          |  M   | ⚪ not started | Match a partial attempt to exactly one App Store Connect build and continue from its current processing or review state; refuse blind retries and duplicate build submissions.                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
|     3 |  3.1 | Configure the private external group and temporary review Museum                    |  S   | ⚪ not started | Manually finish the fixed tester group, beta information, review contact, synthetic demo account, and publicly reachable HTTPS Museum needed for Apple review. Keep secrets and tester identities outside Git and receipts.                                                                                                                                                                                                                                                                                                                                                                                                                           |
|     3 |  3.2 | Prepare, preflight, and publish the first TestFlight candidate                      |  M   | ⚪ not started | Build one higher-numbered candidate from pushed source, independently audit it, pass read-only preflight, authorize one upload, and preserve processing and Beta App Review evidence. Firebase remains available as fallback.                                                                                                                                                                                                                                                                                                                                                                                                                         |
|     3 |  3.3 | Verify external installation, private Museum use, and an in-place update            |  M   | ⚪ not started | Prove that the owner and one invitation-only external tester can install without App Store Connect roles or device registration, select the intended private Museum, preserve state, and receive a higher-build TestFlight update.                                                                                                                                                                                                                                                                                                                                                                                                                    |
|     4 |  4.1 | Rewrite iOS distribution and tester documentation for TestFlight                    |  M   | ⚪ not started | Replace Firebase invitations, registration profiles, Developer Mode, and Ad Hoc device instructions with TestFlight onboarding, review, installation, update, offboarding, recovery, and review-Museum operations across the current documentation set.                                                                                                                                                                                                                                                                                                                                                                                               |
|     4 |  4.2 | Remove the iOS Firebase publisher and distribution contracts                        |  M   | ⚪ not started | Delete only iOS Firebase publication, reconciliation, environment, and test surfaces after Task 3.3 succeeds. Preserve Android Firebase distribution and any unrelated runtime Firebase behavior.                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
|     4 |  4.3 | Mark the Firebase iOS design records historical and preserve release evidence       |  S   | ⚪ not started | Clearly mark the superseded living documents as historical rather than deleting them, and retain prior immutable artifacts, attempts, API evidence, and receipts outside Git.                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
|     4 |  4.4 | Document the as-built TestFlight distribution architecture                          |  S   | ⚪ not started | Write `living_docs/TestFlightIOSDistributionArchitecture.md` from the shipped implementation, including trust boundaries, state transitions, evidence, failure recovery, and the final Firebase boundary.                                                                                                                                                                                                                                                                                                                                                                                                                                             |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

---

## 2. Goal

Replace Firebase App Distribution and Ad Hoc device provisioning as the delivery
path for the configurable self-hosted Ente Photos iOS application with an
invitation-only external TestFlight workflow. V1 is complete when the owner and
one trusted external tester can install the exact audited application without an
App Store Connect role or registered device identifier, select and use their
private Museum service, retain application state through an in-place TestFlight
update, and leave immutable evidence tying the uploaded build to pushed source.
The first external build must also pass Beta App Review through a temporary
publicly reachable Museum containing only synthetic review data. Android
Firebase distribution and unrelated Firebase runtime behavior must remain
unchanged.

The observable success metric is one accepted external TestFlight baseline plus
one accepted higher-build update, with both installations verified on real
devices against the intended private Museum before the iOS Firebase publishing
path is removed.

---

## 3. Architecture / approach

### Selected delivery model

The implementation extends the existing guarded local release workflow instead
of introducing Fastlane or a continuous-integration publishing service.
Preparation remains an offline, non-mutating operation over a clean detached
checkout. Publication is a separate Dart command authenticated to App Store
Connect with a local JSON Web Token (JWT) API key.

```text
pushed source
    |
    v
isolated build + App Store export
    |
    v
read-only IPA + manifest outside Git
    |
    +--> native re-audit
    +--> App Store Connect read-only preflight
    |
    v
exact PUBLISH <release-id> confirmation
    |
    v
one official Apple upload
    |
    v
processing --> validated build --> external group --> Beta App Review
    |                                                    |
    +---------------- resumable reconciliation <---------+
                                                         |
                                                         v
                                                invited testers
                                                         |
                                                         v
                                               private Museum origin
```

The App Store Connect application record, agreements, fixed external tester
group, initial beta metadata, review contact, and review Museum are configured
manually. Automation must validate those resources but must not create or
silently replace them. After upload, automation may operate only on the exact
processed build: assign it to the configured group, submit it for Beta App
Review, and reconcile its state.

The publisher uses Apple's supported upload and App Store Connect interfaces
directly. Task 2.1 must verify the currently supported binary-upload mechanism
and minimum API-key role before Task 2.2 fixes that interface in the release
contract. No Fastlane dependency is introduced.

### Build and identity invariants

- The application bundle remains `me.vanton.ente.photos.selfhosted`.
- The self-hosted target remains core-only and configurable; the official Ente
  application targets and identities do not change.
- Every candidate uses a marketing version and strictly increasing
  `CFBundleVersion` that agree across source, archive, IPA, manifest, Apple
  processing state, and receipts.
- TestFlight candidates use App Store distribution signing and export. The Ad
  Hoc export mode remains available only as a fallback until Task 3.3 succeeds.
- Preparation accepts only a clean pushed commit, regenerates required ignored
  sources in the isolated checkout, audits the resulting IPA as untrusted
  input, and writes collision-safe read-only artifacts outside Git.
- The manifest binds the exact source commit, artifact hash and size,
  application identity, version/build, architecture, entitlements, signing
  mode, configurable endpoint policy, and review Museum origin.
- The publisher never builds or signs. It consumes only the immutable manifest
  and sibling IPA, repeats their audit before and after confirmation, and
  refuses any changed input.

### Review Museum and tester path

External TestFlight builds may require Beta App Review, including the first build
added to an external group. The candidate therefore starts with a temporary,
publicly reachable HTTPS Museum containing a synthetic library and a dedicated
demo account. Review contact details, credentials, beta description, feedback
email, and review notes are entered through App Store Connect and remain valid
until Apple approval.

The build stays configurable. Trusted testers use the existing endpoint
selection flow to move from the review Museum to their private Tailscale-reached
Museum before the temporary service is retired. The review service remains
available until Beta App Review approval and the owner plus external-tester
acceptance in Task 3.3 have both succeeded. It contains no personal library,
production credentials, or route into the private Museum.

### Publication state and evidence

Publication is a state machine rather than one long-running command:

```text
prepared
  -> preflight-passed
  -> upload-authorized
  -> upload-attempted
  -> Apple-processing
  -> processed-and-validated
  -> assigned-to-external-group
  -> waiting-for-beta-review
  -> approved-for-external-testing
  -> tester-accepted
```

Every invocation reads current local evidence and current App Store Connect
state, advances only a valid transition, and exits with an actionable next
command. A processing or review wait is not treated as a failed upload.

The evidence ledger contains:

- the immutable IPA and preparation manifest;
- a preflight snapshot naming only non-secret Apple resource identifiers and
  validated state;
- a partial-attempt receipt written before or immediately around the upload
  mutation;
- processing, group-assignment, and Beta App Review transition evidence; and
- one immutable success receipt after the exact build is externally available.

Receipts may contain opaque Apple identifiers, statuses, timestamps, hashes,
source links, version/build data, and sanitized command results. They must not
contain the API private key, demo password, tester email addresses, private
Museum credentials, or personal Apple account data.

### Failure visibility, rollback, and operational limits

| Failure                                                                                        | Detection and operator-visible result                                                                 | Recovery                                                                                                  |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Wrong app, bundle, team, version, group, agreement, metadata, role, or export-compliance state | Read-only preflight fails before confirmation and names the mismatched field without printing secrets | Correct the manual App Store Connect or local configuration, then rerun preflight                         |
| IPA or manifest changed after preparation                                                      | Hash, permission, source, or native IPA audit fails                                                   | Discard the candidate and prepare a new immutable release                                                 |
| Upload result is missing or ambiguous                                                          | An immutable partial-attempt record exists without a success receipt                                  | Query App Store Connect and use no-upload reconciliation; never retry blindly                             |
| Apple is still processing the build                                                            | Reconciliation reports the current processing state and exits without mutation                        | Resume reconciliation later against the same attempt                                                      |
| Processed build differs from the manifest                                                      | Bundle, version, build, or other returned identity fails validation                                   | Stop; do not assign or submit the build, and prepare a higher-build correction                            |
| Beta App Review rejects the candidate                                                          | Review state and reason are preserved; no automatic resubmission occurs                               | Correct the app, metadata, or review environment and submit a distinct higher build                       |
| Review Museum is unreachable or credentials fail                                               | Preflight health check, Apple review feedback, or acceptance check fails                              | Restore the isolated review service or prepare a corrected higher build; do not expose the private Museum |
| Accepted build has a release defect                                                            | Device acceptance or private Museum behavior fails                                                    | Stop external testing and publish the last known-good source as a higher build                            |
| API key is missing, over-privileged, expired, or compromised                                   | Local permission audit or App Store Connect authentication fails                                      | Stop publication, revoke or replace the key, and re-run read-only preflight                               |

Phases 1 and 2 are pause-safe because the existing Firebase/Ad Hoc process
remains intact. An uploaded Apple build and consumed build number cannot be
rewritten or reused; rollback is forward-only through a higher build, while
testing of a bad build can be stopped. Phase 4 begins only after Task 3.3, so
the prior Firebase iOS release remains the operational fallback until the new
channel has proved both installation and update.

There is no throughput target because this is a single-operator release
workflow. Local validation and App Store Connect preflight must be bounded and
must not wait indefinitely. Apple processing and review are asynchronous
external states, so the SLO is resumability without duplicate upload rather
than completion latency.

The API `.p8` key, issuer and key configuration, signing material, review
credentials, tester identities, private endpoints, and release artifacts stay
outside Git. Child processes receive only the environment values they require,
and logs are sanitized before becoming evidence. Export-compliance answers and
Beta App Review information must agree with the built application; the public
AGPL source link for the exact commit remains part of release evidence.

Operational behavior is checked against Apple's
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview),
[external tester workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers),
[beta test information requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information),
[build upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[export-compliance workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds),
and [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/).

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move from here
> to V1 only with explicit owner approval and a decision-log entry.

| Item                                                                                                       | Status       | Why                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Automate creation of the App Store Connect app, tester groups, agreements, or initial beta metadata        | V1.1 backlog | V1 deliberately validates manually established resources so the release key has a smaller mutation boundary.                                 |
| Move TestFlight signing or publication into continuous integration                                         | V1.1 backlog | V1 keeps Apple credentials and release authority on the guarded operator machine until the local workflow is proven.                         |
| Keep a permanent public review Museum                                                                      | V1.1 backlog | V1 uses a temporary isolated service with synthetic data; a durable service needs its own hosting, monitoring, patching, and abuse controls. |
| Add richer notifications for Apple processing, review, or build expiry                                     | V1.1 backlog | V1 exposes resumable status through the publisher and App Store Connect; remote alerting needs a separate credential and delivery design.    |
| Release the application publicly or privately through the production App Store                             | Out of scope | This initiative is an invitation-only external TestFlight beta for trusted testers.                                                          |
| Give testers App Store Connect roles or use internal TestFlight testing as the primary channel             | Out of scope | Trusted external testers must install without organization access.                                                                           |
| Change Android Firebase App Distribution                                                                   | Out of scope | Android continues using its existing Firebase application, group, publisher, and documentation.                                              |
| Remove Firebase runtime services from any Ente application                                                 | Out of scope | This migration changes only iOS binary distribution, not application runtime integrations.                                                   |
| Delete the Firebase project, iOS application record, historical releases, artifacts, attempts, or receipts | Out of scope | Historical evidence is retained; code and current instructions are retired only after TestFlight acceptance.                                 |
| Expose the private Tailscale Museum to Apple or the public internet                                        | Out of scope | Apple reviews only against the isolated synthetic review service.                                                                            |

---

## 5. Decision log

> Append-only. Newest entries on top. Never delete; if a decision is reversed,
> add a new entry explaining the reversal.

### 2026-07-23 — Treat the Ente account as authorized but unprovisioned

**Decision:** Close the read-only readiness audit with the account control plane
ready and move app-record, signing, profile, and credential creation into Task
1.2.

**Why:** The owner confirmed that New App is enabled, agreements require no
action, and App Store Connect API access is enabled. The bundle has no app
record, while the local audit found no currently visible valid signing identity
or matching App Store profile. These are explicit setup deliverables rather
than authorization blockers.

**Alternatives considered:** Leave the audit open until resources are created,
which would mix read-only discovery with external mutations; or begin export
tooling against invented identifiers, which would weaken the guarded contract.

### 2026-07-23 — Use App Manager as the least publication role

**Decision:** The eventual App Store Connect publication credential must have
the App Manager role, not Developer or Admin.

**Why:** Apple permits a Developer to upload builds, but creating external
TestFlight groups, adding builds to them, inviting external testers, and
starting external testing require Account Holder, Admin, or App Manager. App
Manager is therefore the least role that covers the selected end-to-end
pipeline.

**Alternatives considered:** Developer is sufficient for build upload but not
external-group operations; Admin and Account Holder are broader than the
publisher requires.

### 2026-07-23 — Establish the missing App Store Connect application before build tooling

**Decision:** Add a separate setup task to create the App Store Connect iOS app
record for `me.vanton.ente.photos.selfhosted`, restore a usable local Apple
Distribution identity, and establish its manual App Store provisioning profile
before implementing App Store export.

**Why:** The owner verified that the bundle has no App Store Connect app record,
and the local audit found neither a valid code-signing identity nor a matching
App Store profile. TestFlight groups, beta metadata, builds, and export
compliance cannot exist for this bundle until those prerequisites are
established.

**Alternatives considered:** Hide account and signing creation inside the export
tooling task, which would combine external Apple mutations with repository code;
or begin publisher work without a destination app, which would encode
unverified identifiers and permissions.

### 2026-07-23 — Exclude the unrelated Apple key from the migration

**Decision:** Do not use the downloaded Apple `.p8` key for Ente. It belongs to
another application/team and must be rotated and revoked separately by that
team because its private material was exposed during the local audit.

**Why:** A scoped App Store Connect authentication check rejected the key, and
the owner confirmed that it has no relationship to the Ente team. Reusing or
testing it further would cross application and team boundaries.

**Alternatives considered:** Continue testing the unrelated key against App
Store Connect, which would be unauthorized and cannot establish Ente readiness;
or leave the exposed key active indefinitely, which would preserve a compromised
credential.

### 2026-07-23 — Keep the reference set operational

**Decision:** Link the operative iOS distribution runbook, the planned as-built
TestFlight architecture, and official Apple references. Record the planning
document as `n/a`.

**Why:** Future operators need current procedures and authoritative platform
behavior without carrying every predecessor design into the active migration
record.

**Alternatives considered:** A focused migration lineage including related
living docs, and a full historical lineage including locked-build, upstream,
and continuous-integration records. Both were rejected as unnecessary context
for this operational document.

### 2026-07-23 — Use a guarded hybrid App Store Connect boundary

**Decision:** Configure the app record, agreements, external group, initial beta
metadata, and review environment manually. Automation validates them and may
upload, assign the exact build, submit Beta App Review, and reconcile status.

**Why:** This keeps resource creation and broad account changes under direct
operator control while preserving a repeatable and evidenced release path.

**Alternatives considered:** Fully automate App Store Connect setup, which
requires broader mutation rights; or automate upload only, which fragments the
release state and evidence across manual steps.

### 2026-07-23 — Give Apple an isolated temporary review Museum

**Decision:** Build the configurable candidate with a publicly reachable
review-only Museum containing synthetic data and a demo account. Keep it
available through review and external acceptance, then retire it after testers
have selected their private Museum.

**Why:** Apple cannot reach the private Tailscale service, while external
TestFlight builds can require Beta App Review. The isolated service satisfies
review access without exposing private data or infrastructure.

**Alternatives considered:** Add a bundled offline demo mode, which expands the
application surface and may not represent real behavior; or submit the
Tailscale-only build with explanatory notes, which leaves the reviewer unable
to exercise the application.

### 2026-07-23 — Split publication work at mutation boundaries

**Decision:** Separate authentication and read-only preflight, one-shot upload,
post-upload lifecycle handling, and no-upload reconciliation into distinct
reviewable tasks.

**Why:** Each task has a clear safety boundary, and ambiguous Apple state can be
recovered without mixing a second upload into the same change.

**Alternatives considered:** Split by App Store Connect API layer, which hides
operator outcomes across abstractions; or build vertical publication slices,
which repeats mutation and recovery logic.

### 2026-07-23 — Sequence the migration risk-first and pause-safe

**Decision:** Audit prerequisites first, prove App Store export second, build
the publisher third, prove a real external TestFlight release while Firebase
remains available, and remove iOS Firebase only after installation and update
acceptance.

**Why:** Apple authorization, signing, review access, and asynchronous upload
state are the principal unknowns. Every phase boundary must leave a coherent
release option.

**Alternatives considered:** A thin end-to-end slice would reach upload sooner
but cross unresolved signing and review risks; a documentation-first cutover
would remove the known channel before its replacement is proven.

### 2026-07-23 — Extend the guarded Dart tooling without Fastlane

**Decision:** Reuse the isolated preparation and immutable evidence model, add
App Store distribution signing, and implement App Store Connect JWT,
preflight, upload, lifecycle, and reconciliation behavior in the local Dart
publisher using official Apple interfaces.

**Why:** The repository already has auditable Dart release contracts, native IPA
inspection, exact confirmation, and partial-attempt recovery. Extending that
model avoids a second release framework and preserves the current trust
boundary.

**Alternatives considered:** Fastlane adds mature actions but another dependency
and abstraction over the evidence contract; a mostly manual Xcode/Transporter
workflow reduces code but loses reproducibility and guarded reconciliation.

### 2026-07-23 — Perform a guarded TestFlight cutover

**Decision:** Build the complete App Store Connect pipeline, onboarding,
recovery, and immutable evidence path; prove it with real external installation
and update; then remove iOS Firebase distribution code and current
instructions while retaining historical receipts.

**Why:** Upload alone does not prove that external review, tester installation,
private-server selection, state retention, or updates work.

**Alternatives considered:** A narrow upload-only migration leaves most of the
Firebase operating process intact; a broader App Store release initiative adds
production listing, review, and release concerns that are not needed for the
trusted beta.

### 2026-07-23 — Serve trusted testers through external TestFlight

**Decision:** Replace Firebase/Ad Hoc delivery for the current trusted iOS
testers with invitation-only external TestFlight. Testers do not receive App
Store Connect roles and do not register device identifiers.

**Why:** This removes provisioning-profile refreshes and Firebase installation
steps while retaining a controlled tester population.

**Alternatives considered:** Internal TestFlight requires organization roles;
public links broaden access beyond the trusted group; retaining Firebase/Ad Hoc
does not solve the distribution burden.

---

## 6. Open questions

_Task 1.1 resolves the account questions; Task 3.1 resolves the review-environment
questions. Each resolution moves to §5._

- What app name, stock-keeping unit (SKU), primary locale, and user-access scope
  should Task 1.2 use when creating the App Store Connect record for
  `me.vanton.ente.photos.selfhosted`?
- What fixed external TestFlight group name and identifier will V1 use?
- Which official Apple binary-upload interface is supported by the installed
  Xcode and the selected API-key authentication contract?
- Which export-compliance answers, beta description, feedback address, review
  contact, and review notes must be completed before the first preflight can
  pass?
- What public hostname will the temporary review Museum use, and where will its
  synthetic demo credentials and operational ownership be stored?
- Which exact iOS Firebase-only scripts, tests, environment variables, and
  documentation references remain after the implementation audit, and which
  shared or Android surfaces must be preserved?

---

## 7. Lessons learned

> Populated at the end of each phase. Surprises, anti-patterns discovered, and
> things to do differently next time.

_Empty until first phase completes._
