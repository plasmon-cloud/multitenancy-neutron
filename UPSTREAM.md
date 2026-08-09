# multitenancy-neutron upstream divergence notes

This file records why `multitenancy-neutron` intentionally differs from upstream Neutron and which differences are temporary Phase 1–9 scaffolding rather than long-term `multitenancy-neutron` architecture.

The target relationship is:

> `multitenancy-neutron` = backwards-compatible Neutron + generic multi-tenant execution/allocation + a minimal built-in tenant control plane.

Plasmon is a separate future control plane that consumes `multitenancy-neutron`. Plasmon/Malstorm product concepts such as Element, Isotope, Atom, porter, and product-specific bootstrap tooling are not `multitenancy-neutron` kernel architecture.

## Repository branch model

Within this repository, `dev` is the integration base for version branches such as `version-0.0.1`. Version work should be compared against and eventually merged back into `dev`, not directly into this repository's `main` branch.

References in this document to **upstream Neutron `main`** mean the external/upstream Neutron source baseline, not the `multitenancy-neutron` integration branch.

## Review rule

For every divergence from upstream Neutron:

1. Ask whether the file can now be restored exactly from current upstream Neutron.
2. If not, move as much `multitenancy-neutron` implementation as practical into `multitenancy-neutron`-owned modules and leave one small, obvious seam in the upstream-derived file.
3. Preserve focused tests for every authorization, isolation, persistence, allocation, lifecycle, and compatibility invariant.
4. Never hand-edit generated output merely to preserve a `multitenancy-neutron` delta; change its source or generator instead.

Inline comments should be concentrated at places where a future maintainer could otherwise remove an important invariant while performing an apparently harmless cleanup.

## Core multitenancy-neutron invariants

### Allocation

For a tenant principal and logical application, `multitenancy-neutron` permits at most one usable physical Neutron app instance:

```text
(principal, logical app) -> zero or one physical app_instance
```

Allocation is persistent and idempotent. Repeating allocation for the same principal and logical app must return the same usable physical instance rather than create a second assignment.

The physical app instance/AppScope is the tenant's Neutron execution scope. It is not a Plasmon Atom or another product-level object.

### Authorization and AppScope isolation

The kernel owner retains ordinary Neutron owner authority. Tenant self-enrollment grants tenant access only; it must never imply owner administration or physical deployment authority.

A tenant may use only physical AppScopes granted to that tenant. Direct access to another tenant's physical AppScope must fail even when the caller knows the physical app-instance id.

### Workspace privacy

Browser-local workspace persistence must be scoped by both kernel canister id and principal:

```text
neutron-kernel-workspaces-v2:<canisterId>:<principal>
```

Never migrate the legacy unscoped `neutron-kernel-workspaces-v2` value into a principal-scoped workspace. The old value may belong to another tenant who previously used the same browser and Neutron origin.

### Stable-memory compatibility

`multitenancy-neutron` currently adds these persistent roots:

```text
tenants
app_instances
app_instance_lifecycle
app_catalog
```

Their names and `v1.mo` layouts are upgrade-sensitive. Physical and logical ids stored inside these maps are persistent data too; renaming deployed ids changes the meaning of stored grants, lifecycle records, and catalog mappings.

If `v0.0.1` explicitly declares that historical Malstorm/Phase 1–9 development deployments have no upgrade guarantee, these identities may be redesigned once before release. Otherwise structural changes require migration. Do not casually rename these roots or persisted identifiers.

## Required multitenancy-neutron source divergences

### `apps/kernel/backend/app_instances/Allocation.mo`

**Category:** `multitenancy-neutron` requirement.

Resolves a tenant's already-assigned physical instance for a logical app. Reads remain deterministic if older state contains duplicate grants, while allocation writes must prevent new duplicates. Unusable or retired instances must not be selected.

Protected by `apps/kernel/test/motoko/app_instance_allocation_test.mo` and deployed allocation/isolation assertions in `test/e2e/local-kernel.spec.ts`.

### `apps/kernel/backend/memory/tenants/v1.mo`

**Category:** `multitenancy-neutron` requirement; persistence-sensitive.

Stores tenant principal -> physical app-instance grants. Logical uniqueness is derived through `app_instances`; do not introduce a second logical installation record here.

### `apps/kernel/backend/memory/app_instances/v1.mo`

**Category:** `multitenancy-neutron` requirement; persistence-sensitive.

Stores physical app-instance id -> logical app id. This mapping intentionally separates tenant-visible logical application identity from the physical Neutron execution identity.

### `apps/kernel/backend/memory/app_instance_lifecycle/v1.mo`

**Category:** `multitenancy-neutron` requirement; persistence-sensitive.

Persists physical-instance retirement. Retirement is permanent non-reuse state, not merely a transient capacity flag. A retired physical id must never be returned by future allocation.

**Known test gap:** add a deployed test for `allocate X -> retire X -> allocate same logical app -> assert X is never returned`.

### `apps/kernel/backend/memory/app_catalog/v1.mo`

**Category:** `multitenancy-neutron` requirement; persistence-sensitive.

Stores logical application metadata independently of physical app instances. Preserve that separation; catalog entries are not physical installation records.

### `apps/kernel/backend/main.mo`

**Category:** `multitenancy-neutron` requirement; major upstream-conflict hotspot.

Contains the actor seams for tenant membership/grants, owner-vs-tenant authorization, logical catalog, physical instance registry, lifecycle/retirement, deterministic allocation, AppScope authorization, and owner-only administration.

Keep ordinary Neutron owner semantics intact. Refactor toward `multitenancy-neutron`-owned backend modules so `main.mo` eventually contains mostly imports, service construction, small wrappers, and unavoidable actor/authorization seams.

### `apps/kernel/src/reducer/apps.ts`

**Category:** `multitenancy-neutron` requirement; upstream-conflict hotspot.

Phase 1–9 accumulated logical catalog, pool publishing, capacity, and allocation behavior here. Move `multitenancy-neutron`-specific behavior toward `multitenancy-neutron`-owned modules and keep ordinary upstream install/package reducer behavior as close to upstream as possible.

Compatibility invariant: `multitenancy-neutron` must not fork the `.neutron` package format. Any standard `.neutron` package supported by upstream Neutron must remain compatible with `multitenancy-neutron`.

Known limitation: the Phase 9 runtime publishing prototype intentionally rejects packages with dependencies. Do not describe that prototype as universal upstream-package publishing support until the limitation is removed or clearly separated from ordinary package compatibility.

### `apps/kernel/src/reducer/auth.ts`

**Category:** `multitenancy-neutron` requirement; upstream-conflict hotspot.

Adds tenant self-enrollment, owner-vs-tenant role state, tenant app discovery/allocation, and activation of principal-scoped workspace persistence.

Self-enrollment creates tenant authorization only. The flow must recheck authorization after joining and must not alter ordinary owner authentication semantics.

### `apps/kernel/src/workspace/store.ts`

**Category:** `multitenancy-neutron` requirement; privacy-sensitive.

The principal/canister-scoped persistence key prevents Tenant B from loading Tenant A's persisted workspace when they share a browser and kernel origin. The legacy unscoped key must never be migrated into a scoped tenant workspace.

If possible, move key construction/scope switching into a small `multitenancy-neutron` persistence module so the ordinary workspace store can stay closer to upstream.

### `apps/kernel/src/workspace/Launcher.tsx`

**Category:** current `multitenancy-neutron` requirement; major upstream-conflict hotspot.

Contains the Phase 9 tenant launcher. Required behavior is `Install` when no physical allocation exists and `Open` after allocation. Reopening and reloading must use the same physical instance.

There is a deliberate race fix after allocation: first consult the current physical registry; if the newly allocated instance is absent, perform exactly one authoritative `getApps()` refresh and retry the lookup. Do not replace this with sleeps, polling, or arbitrary retries.

Preferred Phase 10 shape: move this tenant UI to `TenantLauncher.tsx`, restore upstream `Launcher.tsx`, and select the component through one small role-dependent shell seam.

### `apps/kernel/src/workspace/KernelTrayItem.tsx`

**Category:** current `multitenancy-neutron` requirement; upstream-conflict hotspot.

Tenants must not receive owner Settings/system-administration behavior. Prefer moving tenant behavior to `TenantKernelTrayItem.tsx`, restoring upstream `KernelTrayItem.tsx`, and selecting by session role at one small shell seam.

## Hard behavior tests

### `apps/kernel/test/motoko/app_instance_allocation_test.mo`

Covers deterministic same-logical-app resolution, deterministic duplicate handling, unusable-instance skipping, independent logical apps, and missing/unregistered apps.

### `apps/kernel/test/auth.test.ts`

The `multitenancy-neutron`-specific behavior protects tenant self-enrollment followed by an authorization recheck. Preserve ordinary owner authentication behavior as an upstream compatibility requirement.

### `test/e2e/local-kernel.spec.ts`

The Phase 1–9 tenant-boundary test is authoritative even where names still contain stale Plasmon/Element/Atom terminology. Preserve these behaviors while later renaming terminology:

- two tenants can join;
- tenant sessions are authorized but are not owners;
- the developer principal remains owner;
- tenants cannot invoke owner physical-deployment authority;
- owner can invoke that authority;
- repeated allocation of one logical app returns the same physical instance;
- different logical apps allocate independently;
- different tenants receive different physical instances;
- grants do not overlap;
- recreated/reloaded actor state preserves allocation;
- direct physical AppScope calls succeed for the owning tenant;
- cross-tenant physical AppScope calls fail;
- test-created grants are revoked during cleanup.

The tenant launcher test additionally protects `Install -> Open -> reopen/reload same physical instance` behavior.

## Generic Neutron fixes discovered during multitenancy-neutron work

These are not conceptually multi-tenancy features. Retain them only if current upstream Neutron still needs them; otherwise restore upstream and, where appropriate, propose them upstream separately.

### `packages/neutron-scripts/src/motoko.ts`
### `packages/neutron-scripts/src/walk.ts`

Allow multiple Motoko entrypoints to reuse content-hash/danger-analysis work without incorrectly sharing parent-specific dependency edges. Dependency graphs remain entrypoint-specific while hash/source analysis can be reused.

### `flake.nix`

Adds Fontconfig/DejaVu configuration needed for reliable local Playwright Chromium behavior in the Nix development shell.

### `apps/kernel/test/certified_assets_settings.test.ts`
### `apps/kernel/test/certified_assets_settings_controls.isolated.ts`

The isolated process avoids Bun `mock.module()` process-global state poisoning later tests that require the real auth module.

### `apps/kernel/test/helpers/kernel_wrapper.ts`
### `apps/kernel/test/install.test.ts`

Generic test-harness cleanup: assemble the actual kernel wrapper through the shared helper rather than maintaining brittle duplicated wrapper expectations. Keep generic improvements; move `multitenancy-neutron`-specific memory/API assertions to focused `multitenancy-neutron` tests where possible.

### `packages/neutron-compiler/src/assemble.ts`
### `packages/neutron-compiler/test/assemble.test.ts`

The remaining branch delta is small and must be audited line-by-line against current upstream Neutron. Current upstream Neutron already contains active app-instance inventory/AppScope assembler infrastructure; do not assume every remaining line is required by `multitenancy-neutron`.

## Other Phase 1–9 test/build deltas to audit

These changed during Phase 1–9 but are not, by themselves, permanent `multitenancy-neutron` architecture:

```text
apps/kernel/package.json
apps/kernel/test/install_only_guard.isolated.ts
apps/kernel/test/motoko/run.ts
apps/kernel/test/package_artifacts.ts
apps/kernel/test/permission_dialog.test.tsx
apps/kernel/test/privacy_client.test.ts
```

Retain only changes still required by a focused `multitenancy-neutron` or generic-Neutron test/build contract.

## Generated or generator-owned files

Do not add hand-written explanatory comments to these outputs. Document their ownership here and change source/generator inputs instead.

### `apps/kernel/backend/_neutron.mo`

Generated actor wrapper. Owned by the kernel build/assembly pipeline (`npm --workspace neutron-kernel run build`, also exercised by `package`). Do not hand-edit.

### `apps/kernel/neutron.lock.json`

Maintained by the Motoko packaging/memory-lineage pipeline. Normally committed; do not hand-edit lock contents.

### `apps/kernel/neutron.json`

Source metadata contains generator-owned backend function/wrapper/type information. After Motoko API changes, run the normal generator instead of manually repairing generated function data.

### `apps/kernel/certified-assets-candidate-binding.json`

Generated evidence. Regenerate with:

```text
npm --workspace neutron-kernel run certified-assets:candidate-binding:write
```

Verify without writing with:

```text
npm --workspace neutron-kernel run certified-assets:candidate-binding
```

### `package-lock.json`

npm-owned dependency lock. Regenerate through normal npm operations; do not hand-edit.

Generated/untracked build output such as `dist/`, `*.neutron`, and `.mops/` is not source. `apps/kernel/mops.lock` appeared during Phase 9 and was intentionally not committed.

## Temporary Phase 1–9 scaffolding

These are historical bootstrap/control-plane files, not permanent `multitenancy-neutron` production surface:

```text
malstorm-phase0.ndeploy.json
malstorm-phase1a.ndeploy.json
plasmon-app-admin.ts
plasmon-app-pools.json
plasmon-base.ndeploy.json
plasmon-bootstrap.ts
plasmon-capacity.ts
plasmon-provision.ts
plasmon-shards.json
plasmon-tenant-admin.ts
package.json                  # plasmon:* root scripts only
.gitignore                    # .plasmon-generated / plasmon.ndeploy.json entries
```

Useful logic may be genericized into `multitenancy-neutron` tooling, moved to test/support fixtures, or moved to the separate Plasmon repository. Production `multitenancy-neutron` code/docs/tooling should not retain `plasmon` or `malstorm` names unless deliberately used as an external compatibility fixture.

## Duplicate physical-app fixtures

All files under these directories are Phase 1–9 fixtures used to prove physically distinct Neutron app identities. They are not intended as four first-class shipped applications:

```text
apps/demo_001/**
apps/demo_002/**
apps/hello_a/**
apps/hello_b/**
```

Preferred replacement:

```text
one canonical ordinary upstream-compatible .neutron app
        -> test fixture/generator
        -> ephemeral physical app identities for allocation/pool tests
```

The `.DS_Store` files in these directories are accidental and should be removed during cleanup, with a repository-wide `.DS_Store` ignore added.

## Historical documentation requiring rewrite

```text
README.md
TODO.md
doc/architecture.md
```

These contain historical Plasmon/Malstorm product architecture. Do not mechanically rename Plasmon to `multitenancy-neutron`. Rewrite them around generic `multitenancy-neutron` responsibilities and move Element/Isotope/Atom/porter/Plasmon architecture to the separate Plasmon project.

## CI branch policy

### `.github/workflows/kernel-ci.yml`

`dev` is the integration branch for `multitenancy-neutron` version work. The historical `malstorm-phase1` CI target must not return. Keep pull-request CI and normal stable-branch CI as appropriate, but version branches target `dev` for integration.

## Validation baseline

Immediately before Phase 9 closeout, the historical branch passed:

```text
npm --workspace neutron-kernel run package
npm --workspace neutron-kernel test
npm run plasmon:deploy
npm run plasmon:test
```

The focused tenant-launcher Playwright test also passed twice consecutively.

Treat the branch as a validated behavior baseline, not a clean architecture baseline. Ordinary upstream Neutron owner behavior remains a hard compatibility requirement; `multitenancy-neutron` tests supplement upstream package/kernel/E2E gates rather than replacing them.

## Before merging `version-0.0.1` into `dev`

Compare `version-0.0.1` against both `dev` and current upstream Neutron `main`:

- `dev` is the repository integration base and the eventual merge target.
- upstream Neutron `main` is the compatibility/conflict-minimization reference.

For each modified upstream-derived file, first try to restore it exactly to current upstream Neutron. If that is impossible, aim to move 90%+ of `multitenancy-neutron` implementation into `multitenancy-neutron`-owned files and leave one small, explicit, documented seam.