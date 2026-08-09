# multitenancy-neutron upstream divergence notes

This file records why `multitenancy-neutron` intentionally differs from upstream Neutron and how those differences should be maintained.

The target relationship is:

> `multitenancy-neutron` = backwards-compatible Neutron + generic multi-tenant allocation/isolation + a minimal built-in tenant control plane.

Upstream Neutron is the external compatibility reference. Repository integration and release mechanics are intentionally kept out of this document.

## Review rule

For every divergence from upstream:

1. Ask whether the file can be restored exactly to current upstream Neutron.
2. If not, move as much multi-tenant implementation as practical into `multitenancy-neutron`-owned modules and leave one small, obvious seam in the upstream-derived file.
3. Protect authorization, isolation, persistence, allocation, lifecycle, and compatibility invariants with focused tests.
4. Never hand-edit generated output merely to preserve a divergence; change its source or generator instead.

Inline comments should be concentrated at places where a future maintainer could otherwise remove an important invariant during an apparently harmless cleanup.

## Core invariants

### Allocation

For a tenant principal and logical application, `multitenancy-neutron` permits at most one usable physical Neutron app instance:

```text
(principal, logical app) -> zero or one physical app_instance
```

Allocation is persistent and idempotent. Repeating allocation for the same principal and logical app returns the same usable physical instance rather than creating a second assignment.

The physical app instance/AppScope is the execution identity. Workspace tiles are views and must not imply additional allocation.

### Authorization and AppScope isolation

The kernel owner retains normal Neutron owner authority. Tenant self-enrollment grants tenant session access only; it must never imply owner administration or physical deployment authority.

A tenant may use only physical AppScopes granted to that tenant. Direct access to another tenant's physical AppScope must fail even when the caller knows the physical app-instance id.

### Workspace privacy

Browser-local workspace persistence is scoped by both kernel canister id and principal:

```text
neutron-kernel-workspaces-v2:<canisterId>:<principal>
```

Never migrate the legacy unscoped `neutron-kernel-workspaces-v2` value into a principal-scoped workspace. The old value may belong to another tenant who previously used the same browser and kernel origin.

### Stable-memory compatibility

`multitenancy-neutron` adds these persistent roots:

```text
tenants
app_instances
app_instance_lifecycle
app_catalog
```

Their names and persisted layouts are upgrade-sensitive once compatibility with deployed state is promised. Physical and logical ids stored inside these maps are persistent data as well; changing identifier semantics changes the meaning of grants, lifecycle records, and catalog mappings.

## Required source divergences

### `apps/kernel/backend/app_instances/Allocation.mo`

**Category:** required multi-tenant implementation.

Resolves a tenant's already-assigned physical instance for a logical app. Reads remain deterministic if older state contains duplicate grants, while allocation writes prevent new duplicates. Unusable or retired instances are not selected.

Protected by `apps/kernel/test/motoko/app_instance_allocation_test.mo` and deployed allocation/isolation assertions in the multi-tenant E2E coverage.

### `apps/kernel/backend/memory/tenants/v1.mo`

**Category:** required; persistence-sensitive.

Stores tenant principal -> physical app-instance grants. Logical uniqueness is derived through `app_instances`; do not introduce a second logical installation record here.

### `apps/kernel/backend/memory/app_instances/v1.mo`

**Category:** required; persistence-sensitive.

Stores physical app-instance id -> logical app id. This mapping intentionally separates tenant-facing logical application identity from physical Neutron execution identity.

### `apps/kernel/backend/memory/app_instance_lifecycle/v1.mo`

**Category:** required; persistence-sensitive.

Persists physical-instance retirement. Retirement is permanent non-reuse state, not a transient capacity flag. A retired physical id must never be returned by future allocation.

**Known test gap:** add a deployed regression for `allocate X -> retire X -> allocate same logical app -> assert X is never returned`.

### `apps/kernel/backend/memory/app_catalog/v1.mo`

**Category:** required; persistence-sensitive.

Stores logical application metadata independently of physical app instances. Catalog entries are not physical installation records.

### `apps/kernel/backend/main.mo`

**Category:** required seam; major upstream-conflict hotspot.

Contains actor seams for tenant membership/grants, owner-vs-tenant authorization, logical catalog, physical instance registry, lifecycle/retirement, deterministic allocation, AppScope authorization, and owner-only administration.

Keep ordinary Neutron owner semantics intact. The cleanup target is to move implementation into focused `multitenancy-neutron` modules so `main.mo` eventually contains mostly imports, service construction, small wrappers, and unavoidable actor/authorization seams.

### `apps/kernel/src/reducer/apps.ts`

**Category:** required seam; upstream-conflict hotspot.

Contains app-pool publication and capacity behavior in the ordinary Neutron apps reducer.

Compatibility invariant: `multitenancy-neutron` must not fork the `.neutron` package format. Standard packages supported by upstream Neutron must remain compatible.

Known limitation: the current app-pool publishing prototype rejects packages with application dependencies. Treat this as a limitation of that publication path, not as a package-format rule.

Cleanup target: move pool-specific behavior into repository-owned modules while restoring ordinary upstream install/update/uninstall code as closely as possible.

### `apps/kernel/src/reducer/auth.ts`

**Category:** required seam; upstream-conflict hotspot.

Adds tenant self-enrollment, owner-vs-tenant role state, tenant logical-app discovery/allocation, and activation of principal-scoped workspace persistence.

Self-enrollment creates tenant authorization only. The flow rechecks authorization after joining and must not alter ordinary owner authentication semantics.

Cleanup target: isolate tenant/session behavior behind focused modules and leave the upstream auth flow minimally changed.

### `apps/kernel/src/workspace/store.ts`

**Category:** required; privacy-sensitive.

The principal/canister-scoped persistence key prevents Tenant B from loading Tenant A's persisted workspace when they share a browser and kernel origin. The legacy unscoped key must never be migrated into a scoped tenant workspace.

Cleanup target: move scope/key handling into a focused persistence helper if that materially reduces the upstream-derived store delta.

### `apps/kernel/src/workspace/Launcher.tsx`

**Category:** required seam; major upstream-conflict hotspot.

Contains the tenant logical-app launcher. Required behavior is `Install` when no physical allocation exists and `Open` after allocation. Reopening and reloading must use the same physical instance.

There is a deliberate race fix after allocation: first consult the current physical registry; if the newly allocated instance is absent, perform exactly one authoritative `getApps()` refresh and retry the lookup. Do not replace this with sleeps, polling, or arbitrary retries.

Preferred cleanup shape: move tenant behavior to `TenantLauncher.tsx`, restore upstream `Launcher.tsx`, and select the component through one small role-dependent shell seam.

### `apps/kernel/src/workspace/KernelTrayItem.tsx`

**Category:** required seam; upstream-conflict hotspot.

Tenant sessions must not receive owner Settings/system-administration behavior.

Preferred cleanup shape: move tenant behavior to `TenantKernelTrayItem.tsx`, restore upstream `KernelTrayItem.tsx`, and select by session role at one small shell seam.

## Hard behavior tests

### `apps/kernel/test/motoko/app_instance_allocation_test.mo`

Protects deterministic same-logical-app resolution, deterministic duplicate handling, unusable-instance skipping, independent logical apps, and missing/unregistered apps.

### `apps/kernel/test/auth.test.ts`

Protects tenant self-enrollment followed by an authorization recheck while preserving ordinary owner authentication behavior.

### Multi-tenant E2E coverage

The regression coverage protects:

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
- test-created grants are revoked during cleanup;
- launcher `Install -> Open -> reopen/reload` uses the same physical instance.

## Generic Neutron fixes discovered during this work

These are not conceptually multi-tenant features. Retain them only if current upstream still needs them; otherwise restore upstream and, where appropriate, propose the fix upstream separately.

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

Generic test-harness cleanup: assemble the actual kernel wrapper through the shared helper instead of maintaining brittle duplicated wrapper expectations. Keep generic improvements; move multi-tenant memory/API assertions into focused tests where possible.

### `packages/neutron-compiler/src/assemble.ts`
### `packages/neutron-compiler/test/assemble.test.ts`

The remaining repository delta is small and must be audited line-by-line against current upstream. Current upstream already contains active app-instance inventory/AppScope assembler infrastructure; do not assume every remaining line is required here.

## Other test/build deltas to audit

These changed during proof-of-concept development but are not, by themselves, permanent multi-tenant architecture:

```text
apps/kernel/package.json
apps/kernel/test/install_only_guard.isolated.ts
apps/kernel/test/motoko/run.ts
apps/kernel/test/package_artifacts.ts
apps/kernel/test/permission_dialog.test.tsx
apps/kernel/test/privacy_client.test.ts
```

Retain only changes still required by a focused multi-tenant or generic-Neutron test/build contract.

## Repository-specific development tooling

Current local app-pool/deployment helpers use the repository name explicitly:

```text
multitenancy-neutron-app-admin.ts
multitenancy-neutron-app-pools.json
multitenancy-neutron-base.ndeploy.json
multitenancy-neutron-bootstrap.ts
multitenancy-neutron-capacity.ts
multitenancy-neutron-provision.ts
multitenancy-neutron-shards.json
multitenancy-neutron-tenant-admin.ts
```

Generated paths are:

```text
.multitenancy-neutron-generated/
multitenancy-neutron.ndeploy.json
/multitenancy-neutron/templates/<logical-app-id>.neutron
```

These helpers are development/control-plane scaffolding. Useful generic behavior may remain here or move into a dedicated operator package, but kernel APIs and persistence must not depend on a higher-level product model.

## Duplicate physical-app fixtures

The current directories below are proof-of-concept fixtures used to demonstrate physically distinct Neutron app identities:

```text
apps/demo_001/**
apps/demo_002/**
apps/hello_a/**
apps/hello_b/**
```

They are not intended to remain four separately maintained applications.

Preferred replacement:

```text
one canonical ordinary upstream-compatible .neutron app
        -> test fixture/generator
        -> ephemeral physical app identities for allocation/pool tests
```

Generated physical packages should remain outside Git.

## Generated or generator-owned files

Do not add hand-written explanatory comments to generated outputs. Document their ownership here and change source/generator inputs instead.

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

Generated/untracked output such as `dist/`, `*.neutron`, `.mops/`, `.multitenancy-neutron-generated/`, and `multitenancy-neutron.ndeploy.json` is not source.

## Validation baseline

The core validation commands are:

```text
npm --workspace neutron-kernel run package
npm --workspace neutron-kernel test
npm run multitenancy-neutron:deploy
npm run multitenancy-neutron:test
```

Treat the implementation as a behavior baseline, not yet as the final low-conflict architecture. Ordinary upstream Neutron owner/package/runtime behavior remains a hard compatibility requirement; multi-tenant tests supplement those gates rather than replacing them.

## Integration review

Compare modified upstream-derived files against current upstream Neutron. For each file, first try to restore it exactly. If that is impossible, move as much implementation as practical into `multitenancy-neutron`-owned files and leave one small, explicit, documented seam.
