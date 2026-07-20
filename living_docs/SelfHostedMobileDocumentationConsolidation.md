# Self-Hosted Mobile Documentation Consolidation

**Status:** Complete as of 2026-07-20. All project-created mobile self-hosting documentation is inventoried, consolidated, privacy-clean, and validated.
**Started:** 2026-07-20
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `living_docs/FirebaseIOSDistributionArchitecture.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Inventory every project-created document and assign its audience, authority, and lifecycle | M | 🟢 done | Git history from the first locked-iOS task through the current worktree identified eleven project-created Markdown documents plus the modified Photos README entry point. The inventory classifies one build guide, two platform operator guides, one tester guide, two settled architecture companions, five living implementation records, and the README without taking ownership of referenced upstream server manuals. |
| 1 | 1.2 | Audit facts, links, privacy, versions, release state, and current source behavior | M | 🟢 done | Audited all eleven project documents plus the README against source, release trackers, guarded command contracts, and current official Apple/Firebase/Tailscale references. Initial validation resolved all 55 local links; six scripts exist, are executable, and pass Bash syntax; four release commands expose the documented help contracts. Found duplicated tester flows, seven stale status/backlog claims, and deployment-specific paths/hosts/Firebase/profile identifiers, all routed into later correction tasks. |
| 2 | 2.1 | Consolidate shared build, server, account, network, and recovery guidance | M | 🟢 done | Made the build guide the canonical shared command/server reference, replaced personal toolchain/artifact paths with portable private-root variables, removed a stale private rollback path, and routed distribution/testing to their canonical guides. |
| 2 | 2.2 | Consolidate Android operator guidance and remove duplicate procedures | M | 🟢 done | Added the verified build-2159 state, kept operator-controlled Firebase/Tailscale/Museum handoff and recovery, and replaced tester installation/server/media instructions with one link to the shared tester guide. |
| 2 | 2.3 | Consolidate iOS operator guidance and clearly preserve the owner-only limitation | M | 🟢 done | Added the verified owner build-2161 state and explicit non-owner limitation, retained the real-device/Apple-profile/higher-build operator loop, prohibited unverified identifiers, and routed all tester-performed steps to the shared guide. |
| 2 | 2.4 | Finalize the shared tester guide and replace platform-specific tester duplication with links | M | 🟢 done | Finalized one private-value-free Android/iOS guide for identities, Tailscale `/ping`, Firebase installation, iOS registration/wait, server selection, bidirectional media acceptance, troubleshooting, updates, and leaving the test. Both platform runbooks now link to it. |
| 3 | 3.1 | Normalize living and architecture documents with accurate status and supersession links | M | 🟢 done | Labeled locked records as historical, labeled endpoint and Firebase records accurately, corrected completed Android and iOS cross-project claims, preserved deferred non-owner iOS proof, linked current navigation, and replaced personal paths, host/address details, Firebase IDs, and profile UUIDs with privacy-safe descriptions. |
| 3 | 3.2 | Add the central documentation index and link it from current entry points | M | 🟢 done | Added `mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md` with current release state, audience routing, authority map, historical index, private-state boundary, and maintenance checklist. Linked it from the Photos README, current guides, architecture companions, and living records. |
| 3 | 3.3 | Validate all local links, documented commands, privacy rules, and Markdown diffs | S | 🟢 done | Validated 80 local Markdown links/anchors across all 14 project documents; all six scripts exist, are executable, and pass Bash syntax; both build wrappers accept the documented endpoint through `--validate-only`; all four release commands expose their documented help without building or publishing. Source confirms version `1.3.59+2159`, package/bundle identities, SDK 26/36, configurable mode, and fixed Firebase group aliases. The screened private-value scan and `git diff --check` are clean. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting
it and 🟢 done only after its acceptance evidence passes. Describe each task and
wait for approval before implementation unless the owner has explicitly asked
for uninterrupted execution.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a
commit is opened for a task, mirror that title.

---

## 2. Goal

Make the self-hosted Ente Photos mobile documentation accurate, private-data
safe, and understandable to both the owner/operator and a future maintainer.
Completion means every project-created document has one explicit role; every
current procedure has one canonical home; Android and iOS differences remain
visible; tester instructions are shareable without operator secrets; historical
living records remain intact but cannot be mistaken for current instructions;
and a central index routes readers to verified build, distribution, tester,
architecture, and historical material without broken links or contradictory
status claims.

The observable success metric is a complete documentation inventory plus a
validated hub-and-spoke structure in which current source and release state
agree with every operational claim, duplicate step-by-step guidance has been
replaced by links to its canonical owner, and automated checks find no broken
local links, missing documented commands, screened private values, or malformed
Markdown changes.

---

## 3. Architecture / approach

The documentation uses a dual-audience hub-and-spoke model:

```text
Photos README
      |
      v
central self-hosted documentation index
      |
      +--> operator: build guide
      +--> operator: Android distribution guide
      +--> operator: iOS distribution guide
      +--> tester: shared Android/iOS onboarding guide
      +--> maintainer: settled architecture companions
      +--> historian: append-only living implementation records
```

Current operational procedures are authoritative only in the build and
platform distribution guides. The tester guide owns actions a tester performs
on their own device. Architecture companions explain settled system behavior.
Living documents retain decisions, task evidence, superseded identities, and
release history; they may link to current operations but are not installation
manuals. The Photos README is an entry point, not a second runbook.

Initial Git-history inventory:

| Document | Audience | Intended authority | Lifecycle |
|---|---|---|---|
| `mobile/apps/photos/README.md` | Contributor | Entry point to the hub and build surfaces | Current, concise |
| `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md` | Operator and maintainer | Canonical build, audit, preparation, and publication command contracts | Current |
| `mobile/apps/photos/SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md` | Operator | Canonical Android Firebase operations, update, offboarding, and recovery | Current |
| `mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md` | Operator | Canonical Apple/Firebase iOS operations, update, offboarding, and recovery | Current, owner-only release proven |
| `mobile/apps/photos/SELF_HOSTED_TESTER_ONBOARDING_GUIDE.md` | Tester | Canonical Android/iOS invitation, installation, server, acceptance, and support flow | Current and audited |
| `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md` | Maintainer | Settled configurable-endpoint architecture | Current architecture |
| `living_docs/FirebaseIOSDistributionArchitecture.md` | Maintainer and operator | Settled iOS distribution boundaries and owner-tested release path | Current architecture with deferred non-owner proof |
| `living_docs/ConfigurableSelfHostedMobileServer.md` | Maintainer and historian | Implementation tracker and decision evidence | Complete living record |
| `living_docs/FirebaseAndroidDistribution.md` | Maintainer and historian | Android release/distribution tracker and evidence | Complete living record |
| `living_docs/FirebaseIOSDistribution.md` | Maintainer and historian | iOS release/distribution tracker and evidence | V1 complete; non-owner work deferred |
| `living_docs/LockedSelfHostedAndroid.md` | Historian | Superseded locked Android baseline | Historical |
| `living_docs/LockedSelfHostedIOS.md` | Historian | Superseded locked iOS and local-server baseline | Historical |

The project also modified source-adjacent README sections and links to upstream
self-hosting administration documents. Those upstream manuals remain external
dependencies: this consolidation verifies references and compatibility but
does not rewrite unrelated server documentation.

Consolidation is non-destructive. A historical document is never deleted merely
because a current guide supersedes it. Duplicated current instructions are
replaced with a short explanation of why the canonical document applies and a
relative link. Any disagreement between source, private release evidence, and
prose fails the audit until the prose is corrected or clearly labeled
historical.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1
> only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|---|---|---|
| Automated scheduled freshness checks for external Apple, Firebase, and Tailscale behavior | V1.1 backlog | V1 records verification dates and primary sources; scheduled network checks require a separate automation and failure-notification design. |
| Generate a documentation website or custom navigation application | V1.1 backlog | Markdown hub navigation is sufficient for the repository and shareable tester workflow. |
| Rewrite upstream Ente self-hosting installation and administration manuals | Out of scope | This project references those manuals but did not create or take ownership of their general server guidance. |
| Delete or squash historical living documents | Out of scope | Append-only implementation and decision evidence must remain available and clearly labeled rather than erased. |
| Commit private server names, tester identities, device identifiers, Firebase bindings, signing assets, or credentials | Out of scope | Deployment-specific identity and authorization data remain in private external storage. |
| Change application, server, Firebase, Apple, Tailscale, or release state during the documentation audit | Out of scope | Consolidation is a documentation-only operation; external mutations require separate explicit approval. |

**Status values:**

- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred
  work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. If a decision changes, add a new
> entry instead of rewriting history.

### 2026-07-20 — Audit inventory first and keep every phase pause-safe

**Decision:** Inventory and classify every project-created documentation surface
before correcting facts or consolidating instructions. Complete accuracy,
platform consolidation, historical normalization, hub navigation, and final
validation as separate reviewable tasks.

**Why:** The repository contains current operator guides, tester instructions,
settled architecture, entry points, and append-only project evidence. Assigning
authority first prevents a cleanup from deleting history or making a stale
document canonical by accident.

**Alternatives considered:** Fix privacy and stale facts before mapping
ownership, which leaves navigation ambiguous during the audit; or create the
index first, which risks presenting stale documents as current.

### 2026-07-20 — Use a hub-and-spoke documentation structure

**Decision:** Add one central self-hosted mobile documentation index and retain
separate canonical build, Android operator, iOS operator, tester, architecture,
and historical documents beneath it.

**Why:** Each audience needs a different level of detail, while shared links and
explicit authority avoid duplicating the same procedure across platform guides.
This structure preserves both readable operations and the project's reasoning.

**Alternatives considered:** A single handbook would become long and mix
platform responsibilities; platform silos would duplicate shared server,
network, privacy, and account guidance.

### 2026-07-20 — Serve both operators and future maintainers

**Decision:** Optimize current runbooks for the owner/operator while retaining
settled architecture and living evidence for future maintainers. Keep the
tester guide independently shareable and free of operator-only secrets.

**Why:** An operator needs concise safe procedures, while a future maintainer
needs identities, boundaries, rejected alternatives, and release provenance.
Neither audience should have to extract its workflow from the other's record.

**Alternatives considered:** Operator-only documentation would lose design
context; contributor-only documentation would make recurring distribution and
recovery needlessly difficult.

### 2026-07-20 — Consolidate thoroughly without adding a new architecture companion

**Decision:** Correct stale facts and links, assign one canonical owner per
procedure, replace duplicates with links, normalize historical status, and add
the central index. Reuse the existing mobile endpoint and iOS distribution
architecture companions rather than creating another architecture document.

**Why:** The existing architecture companions already explain runtime and
distribution boundaries. The missing artifact is a documentation ownership map
and reader-oriented hub, not another description of the application.

**Alternatives considered:** A narrow audit would leave duplication and unclear
authority; a strategic automation project would exceed the immediate cleanup
by introducing scheduled external checks and archival policy.

---

## 6. Open questions

_None. The owner asked for the approved consolidation to proceed with minimal
interaction; new questions are raised only if current evidence cannot resolve a
material contradiction safely._

---

## 7. Lessons learned

- Git history is the reliable scope boundary for distinguishing documents this
  project created from upstream self-hosting manuals it merely references.
- Audience and authority need to be assigned before deduplication. Similar text
  in a historical tracker and an operator runbook serves different purposes
  even when both are technically correct.
- Privacy review must include historical evidence, not only current runbooks.
  Absolute local paths, private network values, Firebase bindings, and profile
  identifiers can outlive the task that originally made them useful.
- Platform asymmetry belongs in the index and operator guide. Android has real
  non-owner proof; iOS remains owner-only until a real second iPhone or iPad
  completes the full registration, reprovisioning, and acceptance chain.
