# Plasmon TODO

This file tracks Plasmon-specific work on top of Neutron.

## Priorities

- **P0** — blocks productive development or the current product proof.
- **P1** — required for a usable Plasmon MVP.
- **P2** — important follow-on architecture/product work.
- **P3** — later optimization or expansion.

## Product-model guardrail

**Atom is the Plasmon equivalent of a Sandstorm grain.**

An Atom is a porter-defined isolated unit created with an Element, usually the smallest independently owned/shared data object that makes sense for that application. Examples: one document, spreadsheet, kanban board, Git repository, blog, chat room, mailbox, notebook, photo album, or image.

The porter chooses the granularity. Sandstorm describes this as an editorial decision and recommends the smallest useful **unit of sharing**.

Therefore:

- `Element` = logical application/package;
- `Isotope` = version/build/runtime profile of an Element;
- `Atom` = porter-defined user object/grain created by an Element;
- Neutron `app_instance` / `AppScope` = physical execution and authorization substrate;
- **Atom is not synonymous with `app_instance`**;
- installing/making an Element available is not the same operation as creating an Atom;
- one installed Element may create many Atoms;
- physical app-instance capacity must not be called Atom capacity unless the final Atom→AppScope design explicitly makes them 1:1.

Sandstorm references:

- https://docs.sandstorm.io/en/latest/developing/handbook/
- https://sandstorm.io/how-it-works
- https://docs.sandstorm.io/en/latest/vagrant-spk/packaging-tutorial/

## Completed foundation

- [x] **P0 — AppScope tenant isolation**
  - Kernel/owner methods remain owner-only.
  - Non-owner app calls are authorized against the exact physical app scope.
- [x] **P0 — Persistent tenant grants**
  - Tenant membership and physical app grants survive upgrades.
- [x] **P0 — Generic app-instance registry**
  - Logical apps map to registered physical app instances.
- [x] **P0 — Dynamic available-app catalog**
  - Tenants can discover logical apps with available unassigned physical capacity.
- [x] **P0 — Tenant self-service physical allocation**
  - A tenant requests a logical app; the kernel assigns one installed, unassigned physical instance.
- [x] **P0 — Safe physical-instance retirement**
  - Retired physical app instances are not reusable.
- [x] **P0 — Tenant onboarding and workspace isolation**
  - Tenant workspace state is scoped by canister and principal.
- [x] **P0 — Generated bootstrap physical capacity**
  - Development bootstrap can generate physical app instances from declarative pool configuration.
- [x] **P0 — Owner/tenant UI boundary**
  - Tenant sessions do not expose privileged kernel controls.
- [x] **P0 — Cross-tenant security regression test**
  - Owner/tenant role checks, install authorization, unique physical allocations, and cross-AppScope rejection are covered.
- [x] **P0 — Browser Publish Element prototype**
  - Owner uploads one dependency-free `.neutron` package.
  - Browser fans the package out into multiple physical app identities in memory.
  - All physical instances compile in one batch.
  - Owner approves once.
  - One Neutron self-upgrade installs the batch.
  - Logical app metadata and physical instances are registered atomically afterward.

## Phase 9 — First tenant app allocation closeout

Phase 9 establishes the first persistent logical-app installation/execution-allocation path for tenants.

**Phase 9 does not define Atom semantics.** Its physical `app_instance` allocation is a substrate proof, not a claim that one tenant+Element allocation equals one Atom.

### Validated

- [x] **One physical instance per tenant + logical app**
  - Allocation implements `(principal, app_id) -> app_instance_id`.
  - Repeated allocation of the same logical app returns the same physical instance.
  - Different apps allocate independently.
  - Different tenants cannot receive the same physical instance.
- [x] **Persistent installation mapping**
  - Installation is derived from persistent tenant grants plus the physical app registry.
  - Reloading/recreating the actor client returns the same physical instance.
- [x] **Exact AppScope authorization**
  - A tenant can call its own allocated physical app.
  - Cross-tenant physical app calls are rejected.
- [x] **Tenant Install → Open launcher flow**
  - A new tenant sees an installable logical Hello entry.
  - Clicking Install allocates a physical Hello instance.
  - The launcher transitions from Install Hello to Open Hello.
- [x] **Multiple workspace Tiles reuse one physical instance**
  - Opening an installed logical app again creates another Tile.
  - Tile creation does not allocate another physical app instance.
  - Multiple Tiles can point to the same physical app instance.
- [x] **Reload preserves installation**
  - After browser reload and tenant login, Hello remains Open rather than returning to Install.
- [x] **Focused browser E2E passes**
  - The Phase 9 tenant launcher Playwright test passed on August 9, 2026.
  - Earlier failures were test issues: Chromium font configuration, obsolete launcher selection/wait behavior, and stale grants left by interrupted test runs.
- [x] **Nix/WSL Chromium runtime fixed**
  - Development shell supplies Fontconfig + DejaVu fonts.
  - Chromium no longer aborts in Skia/Fontconfig during Playwright login.
- [x] **Temporary Phase 9 browser diagnostics removed**
- [x] **Generic tenant memory identity**
  - `memory/malstorm_tenants/v1.mo` was removed before merge.
  - Canonical memory identity is `tenants` / `memory/tenants/v1.mo`.
  - Generated wrapper and lock state use the generic identity.
- [x] **Kernel test suite green after tenant-memory rename**
  - JS/TS and Motoko kernel tests pass after the structural rename and auth terminology update.

### Remaining before Phase 9 is complete

- [ ] **Finish browser-test isolation validation**
  - Automated browser test uses a dedicated tenant identity.
  - Test setup/finally clears that principal's grants so interrupted runs cannot poison the next run.
  - Run the focused browser test twice consecutively without reinstall or manual cleanup.
- [ ] **Remove remaining Plasmon product vocabulary from generic Neutron behavior**
  - Neutron production implementation should use app, app instance, tenant, grant, allocation, and runtime.
  - Product terms Element, Atom, Isotope, and Plasmon belong in Plasmon UX/docs/integration tooling.
  - Do not remove legitimate product terminology from explicitly Plasmon-facing code or docs.
- [ ] **Genericize Phase 9 test terminology**
  - Rename product-specific E2E test names/local variables when they are testing generic Neutron behavior.
  - Keep explicitly Plasmon bootstrap/publishing integration tooling named Plasmon.
- [ ] **Run final terminology audit**
  - Review every hit rather than performing a blind replacement:
    ```bash
    git diff 33585fe..HEAD | grep -Ein 'plasmon|malstorm|element|atom|isotope'
    grep -RIn 'malstorm_tenants' apps/kernel --exclude-dir=node_modules
    ```
- [ ] **Run final Phase 9 validation**
  - Kernel package.
  - Kernel JS/TS + Motoko tests.
  - Clean local deployment/bootstrap.
  - Focused tenant browser E2E twice consecutively.
  - Full Plasmon E2E suite.
  - Verify generated candidate binding matches source.
- [ ] **Produce clean Phase 9 history**
  - Base commit: `33585feee066dbf0f0ad01e33bc86c72eccfdae6`.
  - Create a clean/squashed Phase 9 commit based on that base.
  - Move `malstorm-phase1` only after the clean squash passes validation.
  - Do not modify `main`.

## Phase 10 — Porter-defined Atom model + Notepad proof

This is the first phase that should introduce **real Atom semantics**.

### P0 — Define the porter contract

- [ ] **Define Atom granularity metadata**
  - Porter declares what one Atom represents for the Element.
  - Include a human noun such as `document`, `board`, `repository`, or `notebook` for shell UX.
  - Decide singular/plural metadata and create-action wording.
  - Granularity belongs to the porter, not to a global Plasmon rule.
- [ ] **Separate Element availability/install from Atom creation**
  - Installing/making an Element available must not implicitly mean “the tenant owns one Atom.”
  - An installed Element can create zero, one, or many Atoms.
- [ ] **Define stable Atom identity**
  - Atom ID survives Tile close/open and normal page reload.
  - Tile ID is not Atom ID.
  - Physical `app_instance_id` is not automatically Atom ID.
- [ ] **Define Atom lifecycle API**
  - create;
  - list/discover owned/shared Atoms;
  - open;
  - rename/title metadata;
  - delete/trash/retire;
  - future import/export/clone hooks without implementing all of them now.
- [ ] **Define Atom ownership and sharing boundary**
  - Atom is private to its creator/owner by default.
  - Sharing must target a specific Atom, not implicitly every Atom of an Element.
  - Future permission roles can be layered onto the Atom boundary.
- [ ] **Define Atom → Neutron execution mapping**
  - Decide how the porter-declared Atom maps to Neutron `app_instance` / `AppScope` isolation.
  - Evaluate a strict 1 Atom ↔ 1 AppScope model because it most closely matches Sandstorm grain isolation.
  - If any other mapping is allowed, make it explicit and preserve independent Atom security/ownership semantics.
  - Do not silently infer Atom identity from the Phase 9 tenant app-instance allocation.
- [ ] **Define physical capacity semantics after Atom mapping**
  - Clarify whether creating an Atom consumes a physical precompiled app instance.
  - Clarify how capacity expands when a tenant creates many Atoms.
  - Rename current owner UI from “Atom capacity” to physical/execution capacity until the mapping is settled.

### P0 — Notepad acceptance implementation

- [ ] **Create a minimal Notepad Element**
  - One Notepad document is one Atom.
  - The app edits exactly one Atom/document at a time, following the Sandstorm grain model.
- [ ] **Create multiple document Atoms from one Element**
  - Tenant installs/gets access to Notepad once.
  - Tenant creates document A → Atom A.
  - Tenant creates document B → Atom B.
  - Tenant creates document C → Atom C.
  - All remain independently discoverable/openable.
- [ ] **Atom-specific workspace behavior**
  - Opening Atom A twice may create multiple Tiles pointing to Atom A.
  - Opening Atom B creates a Tile for B, not another view of A.
  - Closing a Tile does not delete its Atom.
- [ ] **Atom-specific persistence**
  - Text in A does not appear in B.
  - Reload preserves Atom IDs and contents.
  - Reopening each Atom returns its own data.
- [ ] **Atom isolation/security regression**
  - A tenant cannot access another tenant's private document Atom without an explicit future sharing grant.
  - Compromise/access to Atom A must not imply access to unrelated Atom B.
- [ ] **Porter declaration proof**
  - Notepad package/porter metadata declares its Atom noun as `document`.
  - Plasmon shell uses that declaration for Create/Open UX rather than hardcoding Notepad semantics.

## P0 — Developer experience

- [ ] **Add a frontend development server with watch/HMR**
  - `TSX`/CSS edits must not require `neutron-kernel package` + canister redeploy.
  - Local frontend should talk to the existing PocketIC canister/gateway.
  - Target workflow:
    - start PocketIC/Neutron once;
    - run a frontend dev server;
    - edit frontend files;
    - HMR or auto-refresh in seconds.
  - Full package/deploy remains the integration path.

- [ ] **Add incremental/build caching to the Neutron kernel pipeline**
  - Avoid rebuilding unchanged frontend, Motoko, compiler inputs, and package artifacts.
  - Identify stable cache keys for each expensive stage.
  - Reuse unchanged generated actor/module work where safe.
  - Document cache invalidation rules.
  - Add timing output so cache effectiveness is measurable.

- [ ] **Cache content-addressed Motoko modules in the browser/compiler**
  - Runtime publishing currently refetches many `/mo/<hash>.mo` modules.
  - These paths are content-addressed and therefore natural immutable-cache candidates.
  - Repeated Element publishes should reuse local module content whenever the hash is unchanged.
  - Measure first-publish versus subsequent-publish request count and compile latency.

- [ ] **Reduce avoidable browser request/preflight overhead**
  - Current local publish traces contain many API POSTs plus corresponding CORS `OPTIONS` requests.
  - Classify required deployment calls versus redundant state/query traffic.
  - Prefer same-origin/local-dev routing where practical.
  - Do not weaken IC authorization or install-journal safety to reduce request count.

- [ ] **Handle stale frontend chunks after self-upgrade/redeploy**
  - A page loaded before deployment can reference frontend chunks removed by the new deployment.
  - Detect failed/stale chunk loads and offer or perform a safe reload.
  - Production users should not need to know that a canister upgrade replaced static assets.

## P0 — Current Publish Element UI

- [ ] **Finish Publish Element form styling**
  - Default initial **physical app-instance capacity**: 4 for the current POC.
  - Do not label this Atom capacity until Phase 10 defines the mapping.
  - Capacity field should match the existing theme.
  - Description field should use normal themed input styling and full usable width.
  - Keep raw Neutron File/URL installation out of the normal Plasmon launcher workflow.

- [ ] **Finish tenant new-Element launcher tile**
  - Show a proper icon/action affordance.
  - Show the full Element name.
  - Show the Element description when present.
  - Before Phase 10, action represents installing/opening the Element execution allocation.
  - After Phase 10, Element UX should expose the porter-defined create noun, e.g. `New document`.
  - Match normal launcher tile dimensions, spacing, hover, focus, and dark/light theme behavior.

- [ ] **Verify description round-trip**
  - Owner-supplied publish description must be persisted in the logical app catalog.
  - Tenant `kernel_app_catalog_get` must return it.
  - Launcher must display it.

- [ ] **Add publishing progress/error UX**
  - Distinguish validation, compiling, approval, staging, uploading, activating, and registry steps.
  - Surface actionable errors without requiring DevTools.
  - Make cancellation semantics explicit where cancellation is still safe.

## P0 — Finish runtime publishing proof

- [ ] **Complete tenant physical-allocation proof for a runtime-published Element**
  - Tenant A allocates one physical instance.
  - Tenant B allocates a different physical instance.
  - Tenant A cannot call Tenant B's physical AppScope.
  - Tenant B cannot call Tenant A's physical AppScope.
  - Published Element remains visible while usable physical capacity exists.
  - Do not call these allocations Atoms; Phase 10 defines Atom creation.

- [ ] **Add permanent E2E coverage for Publish Element**
  - Owner-only publish.
  - One approval for a multi-instance physical batch.
  - Correct physical IDs.
  - Logical catalog registration.
  - Tenant physical allocation.
  - Cross-tenant rejection.
  - Registry failure handling after a committed deployment.

## P1 — Physical capacity management

- [ ] **Add physical execution capacity**
  - Owner selects an existing Element and requests additional physical app-instance capacity.
  - Read the Element's existing physical instance IDs.
  - Allocate the next suffixes, e.g. `notes_005` through `notes_008`.
  - Compile/install all new physical instances in one batch.
  - Register only the new instances under the existing logical app.
  - Preserve existing tenant state and assignments.
  - Revisit suffix/pool semantics after Phase 10 defines Atom→AppScope mapping.

- [ ] **Physical capacity policy**
  - Default initial capacity should be small and demand-driven; current POC target is 4.
  - Avoid large speculative pools.
  - Define low-water/high-water thresholds for future automatic expansion.
  - Batch expansion so every individual allocation does not force a self-upgrade.

- [ ] **Elements admin view**
  - Logical Element name and description.
  - Package/version information.
  - Physical execution capacity.
  - Allocated/free/retired physical app instances.
  - `Add Capacity`.
  - Future upgrade/Isotope controls.
  - Atom counts belong in a separate Atom-aware view after Phase 10.

- [ ] **Tenant admin view**
  - Principal.
  - Installed/allocated Elements and physical execution scopes.
  - Owned/shared Atoms once Phase 10 lands.
  - Logical Element for each Atom.
  - Retired/revoked state.
  - Owner actions where appropriate.

## P1 — Deployment and persistence

- [ ] **Make runtime-published state the production source of truth**
  - `plasmon-app-pools.json` is a development/bootstrap mechanism, not the production catalog.
  - Production operation must not require editing static pool JSON to publish an Element.

- [ ] **Preserve dynamically published Elements across Plasmon/Neutron upgrades**
  - A kernel/platform upgrade must rebuild/self-upgrade from the currently installed app inventory plus the new kernel.
  - Do not reconstruct production state solely from bootstrap configuration.
  - Define recovery behavior if an upgrade fails after compilation but before commit.
  - After Phase 10, Atom IDs/data must survive Element/Isotope/platform upgrades.

- [ ] **Reduce development bootstrap**
  - Keep only minimal Hello/Demo physical capacity needed for tests.
  - Current development target: 2 Hello + 2 Demo, or less when test coverage no longer needs both.
  - Eventually allow an empty Plasmon deployment plus runtime publishing.

- [ ] **Document stable-memory migration rules**
  - Stable-memory identities become compatibility constraints once shipped.
  - Phase 9 tenant memory was genericized to `tenants` before merge.
  - After an identity ships, future renames require an explicit migration/compatibility plan.

## P1 — Owner/admin model

- [ ] **Production owner bootstrap**
  - Define how the first production owner principal is established without deterministic local test seeds.
- [ ] **Owner management UI/API**
  - Add/revoke additional administrator principals.
  - Preserve a safe recovery path.
- [ ] **Separate normal owner UX from low-level Neutron administration**
  - Plasmon owner flows should use Element/Isotope/Atom concepts where those concepts are actually defined.
  - Advanced raw Neutron install/admin controls may remain available behind an explicit advanced surface.

## P1 — Security and lifecycle

- [ ] **Runtime-publish atomicity/recovery audit**
  - Deployment can commit before logical pool registration.
  - Define deterministic recovery/reconciliation for this split boundary.
- [ ] **Atom deletion/retirement semantics**
  - Define trash/delete semantics for a logical Atom separately from physical app-instance retirement.
  - Never accidentally expose prior Atom data by recycling an execution scope unsafely.
- [ ] **Catalog/registry consistency checks**
  - Detect installed-but-unregistered physical apps.
  - Detect registered-but-not-installed physical apps.
  - Provide owner repair tooling.
- [ ] **Physical capacity exhaustion behavior**
  - Clean UX when an Element cannot create/allocate the execution scope it needs.
  - Owner warning and Add Capacity path.
  - Atom creation errors must distinguish product limits from physical-capacity exhaustion.

## P2 — Isotopes / Element upgrades

- [ ] **Make Isotope a first-class product concept**
  - Product meaning: a version/build/runtime profile of an Element.
  - Implementation may remain `version`, `build`, or `package`.
- [ ] **Define Atom upgrade policy**
  - Existing Atom under a new Isotope versus migration to a replacement execution scope.
  - Per-tenant staged rollout.
  - Rollback.
  - Stable-memory/data compatibility.
- [ ] **Support multiple Isotopes of one Element**
  - Example: stable and beta variants.
  - Define whether new Atoms choose an Isotope or follow an Element channel.

## P2 — Package dependencies / composition

- [ ] **Design Atom-aware dependency mapping**
  - Initial Publish Element intentionally rejects package dependencies.
  - Decide whether a specific Atom depends on a per-Atom service scope, tenant-shared service, or globally shared service.
  - Do not assume matching physical suffixes imply matching Atom identity.
- [ ] **Implement dependency-aware publishing only after mapping semantics are explicit**
  - Do not silently copy logical dependency IDs into physical app-instance manifests.

## P2 — Sharding

- [ ] **Shared-shard capacity model**
  - One shared Neutron canister is the default.
  - Add shards only when capacity/scale requires them.
- [ ] **Cross-shard tenant identity and Atom behavior**
  - Tenant should see one Plasmon experience even if their Atoms/execution scopes span shards.
  - Stable Atom identity must not depend on a transient UI Tile or accidental physical placement.
- [ ] **Shard placement policy**
  - Free tier shared placement.
  - Future paid/dedicated canister placement.
- [ ] **Shard health/capacity telemetry**
  - Cycles.
  - Memory.
  - Installed physical app count.
  - Compile/install limits.

## P2 — Admin/dashboard

- [ ] **Plasmon Admin dashboard**
  - Elements.
  - Isotopes.
  - Atoms.
  - Tenants.
  - Shards.
  - Physical execution capacity.
  - Cycles/memory/burn.
  - Recent publish/upgrade operations.
- [ ] **Operational warnings**
  - Low cycles.
  - Low physical execution capacity.
  - Failed or incomplete registry operation.
  - Near Neutron installed-app product limit.

## P3 — Scale and performance research

- [ ] **Re-measure compile/install scaling**
  - Physical app count versus compile time.
  - Physical app count versus Wasm size.
  - Physical app count versus module/request count.
  - Physical app count versus install cycle cost.
- [ ] **Investigate Neutron's current ~256 app product limit**
  - Treat it as a tested product bound, not an ICP protocol limit.
  - Raise only with empirical scale tests.
- [ ] **Explore code/template dedup opportunities**
  - Preserve Atom isolation requirements while avoiding redundant compile/package work where possible.
