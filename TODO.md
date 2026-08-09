# multitenancy-neutron TODO

This file tracks work required to turn the current behavior baseline into a clean, reviewable multi-tenant Neutron implementation.

See [UPSTREAM.md](UPSTREAM.md) for the divergence inventory and [doc/architecture.md](doc/architecture.md) for the runtime model.

## Completed foundation

The current implementation already demonstrates the essential multi-tenant behavior:

- [x] Tenant membership keyed by principal.
- [x] Physical app-instance grants per tenant.
- [x] Logical app catalog separate from physical Neutron app identities.
- [x] Physical app-instance registry mapping instances to logical apps.
- [x] Persistent app-instance retirement state.
- [x] Deterministic, idempotent allocation.
- [x] At most one usable physical instance per `(principal, logical app)`.
- [x] Different tenants can receive different physical AppScopes for the same logical app.
- [x] Exact physical AppScope authorization rejects cross-tenant access.
- [x] Tenant self-enrollment does not grant owner authority.
- [x] Owner-only deployment/catalog/pool administration remains distinct from tenant access.
- [x] Tenant launcher exposes logical apps and transitions from `Install` to `Open` after allocation.
- [x] Reopening/reloading a logical app reuses the same physical allocation.
- [x] Browser workspace persistence is scoped by kernel canister id and principal.
- [x] App-pool generation/deployment helpers use repository-generic naming.
- [x] Legacy product-specific names removed from active root tooling and current multi-tenant UI paths.

## P0 — validation baseline

Before deeper architectural cleanup, preserve and validate the existing behavior baseline.

- [ ] `npm --workspace neutron-kernel run package`
- [ ] `npm --workspace neutron-kernel test`
- [ ] `npm run multitenancy-neutron:deploy`
- [ ] `npm run multitenancy-neutron:test`
- [ ] Run ordinary upstream Neutron E2E coverage required by the modified upstream-derived files.
- [ ] Confirm no stale higher-level product terminology remains in runtime code, tests, scripts, filenames, or repository documentation.

## P1 — minimize upstream frontend conflicts

- [ ] Create `TenantLauncher.tsx` and move tenant-only catalog/allocation UI out of `Launcher.tsx`.
- [ ] Restore `Launcher.tsx` as close to current upstream Neutron as possible.
- [ ] Create `TenantKernelTrayItem.tsx` for tenant-specific tray behavior.
- [ ] Restore `KernelTrayItem.tsx` as close to upstream as possible.
- [ ] Keep only a small role-selection seam in the workspace shell.
- [ ] Move principal-scoped workspace persistence helpers into a focused multi-tenancy module if that materially reduces the `store.ts` delta.

## P1 — minimize upstream backend conflicts

- [ ] Extract tenant membership/grant logic from `apps/kernel/backend/main.mo` into focused backend modules.
- [ ] Extract app catalog, physical registry, allocation, and lifecycle logic from `main.mo` where the actor boundary does not require it to remain inline.
- [ ] Keep owner-vs-tenant authorization rules explicit at actor/public-method seams.
- [ ] Preserve exact AppScope authorization; do not replace physical-scope checks with logical-app checks.
- [ ] Audit all newly introduced stable-memory roots before declaring upgrade compatibility.

## P1 — minimize reducer conflicts

- [ ] Move logical catalog/allocation session helpers out of `apps/kernel/src/reducer/auth.ts` where possible.
- [ ] Move app-pool publication/capacity code out of `apps/kernel/src/reducer/apps.ts` into repository-owned modules.
- [ ] Keep ordinary Neutron install/update/uninstall behavior upstream-compatible.
- [ ] Preserve the one-authoritative-refresh launcher race fix after allocation; do not replace it with sleeps, polling, or arbitrary retries.

## P1 — complete lifecycle coverage

- [ ] Add a deployed regression test for retirement non-reuse:

  ```text
  allocate physical instance X
  retire X
  allocate the same logical app again
  assert the new allocation is not X
  ```

- [ ] Verify retired instances remain unavailable after actor/client recreation.
- [ ] Verify a retired id cannot be reintroduced through owner grant or pool-registration paths.

## P1 — replace copied physical-app fixtures

The current proof-of-concept fixtures duplicate full application trees:

```text
apps/demo_001/
apps/demo_002/
apps/hello_a/
apps/hello_b/
```

Replace them with one canonical ordinary `.neutron` application per logical app plus a test/generation step that derives physical identities for pool tests.

- [ ] Remove copied source trees after the generator-backed fixture path is proven.
- [ ] Keep generated physical packages out of Git.
- [ ] Ensure fixture generation does not alter the `.neutron` package format.

## P1 — upstream audit

Several changes were discovered while implementing multi-tenancy but are not themselves multi-tenant functionality. Audit them against current upstream Neutron and either restore upstream or keep/propose the generic fix separately:

- [ ] `packages/neutron-scripts/src/motoko.ts`
- [ ] `packages/neutron-scripts/src/walk.ts`
- [ ] `flake.nix`
- [ ] certified-assets settings test isolation changes
- [ ] kernel wrapper test helper changes
- [ ] remaining `packages/neutron-compiler/src/assemble.ts` delta

### Generated files

- [ ] Confirm `apps/kernel/backend/_neutron.mo` is generated only from source/config inputs.
- [ ] Regenerate `apps/kernel/neutron.lock.json` using the normal packaging pipeline.
- [ ] Regenerate generated portions of `apps/kernel/neutron.json` through the normal generator.
- [ ] Regenerate `apps/kernel/certified-assets-candidate-binding.json` through its owning command.
- [ ] Regenerate `package-lock.json` only through npm.

Do not add hand-maintained divergence solely to generated output.

## P1 — app-pool maturity

The current pool-publishing path is sufficient for the proof of concept but not yet a complete generic publication system.

- [ ] Support ordinary application dependency graphs when deriving physical app instances.
- [ ] Define collision-safe physical app-instance naming beyond the current numeric suffix convention.
- [ ] Define pool-capacity limits and failure behavior as explicit runtime policy.
- [ ] Define how pool expansion interacts with package upgrades.
- [ ] Define how a logical app update migrates or replaces existing physical instances.
- [ ] Define whether an exhausted app remains discoverable to unallocated tenants.
- [ ] Define owner-visible pool health and available/assigned/retired counts.

The package format itself must remain the standard upstream `.neutron` format.

## P1 — administration and control plane

The current root scripts are development helpers, not a final control-plane API.

- [ ] Define a minimal supported administration interface for logical apps, pools, capacity, tenant grants, and retirement.
- [ ] Decide which development helpers remain in this repository versus a separate operator/control-plane package.
- [ ] Keep tenant-facing APIs self-scoped wherever possible.
- [ ] Keep physical deployment and pool administration owner-only.
- [ ] Avoid introducing product-specific concepts into kernel persistence or APIs.

## P2 — deployment topology

Multi-tenancy semantics should not depend on a particular hosting topology.

- [ ] Document supported single-host and multi-host/sharded deployment modes.
- [ ] Keep allocation decisions deterministic within the authority responsible for a pool.
- [ ] Define capacity discovery between hosts before introducing cross-host allocation.
- [ ] Avoid embedding external control-plane ownership concepts into the kernel data model.

## P2 — performance and developer experience

- [ ] Measure pool-generation cost as physical instance counts grow.
- [ ] Reduce repeated compilation/module work where identical package content permits safe reuse.
- [ ] Evaluate build/HMR paths without weakening package validation or AppScope isolation.
- [ ] Add focused benchmarks before introducing caching that changes compiler or deployment behavior.

## Review criteria

Before integration review:

1. All cleanup items required for the intended scope are complete.
2. The full naming audit contains no stale higher-level product terminology in production code, tests, scripts, filenames, or repository documentation.
3. The retirement non-reuse gap is covered by a deployed test.
4. Standard `.neutron` package compatibility remains intact.
5. Owner behavior continues to match ordinary Neutron expectations.
6. Multi-tenant allocation and cross-tenant isolation tests pass.
7. Every remaining upstream-derived code delta has a documented reason in [UPSTREAM.md](UPSTREAM.md).
