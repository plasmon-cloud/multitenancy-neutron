# multitenancy-neutron architecture

## 1. Purpose

`multitenancy-neutron` extends Neutron so one kernel can host mutually isolated tenant sessions and allocate ordinary Neutron applications from shared physical capacity.

The design deliberately stays inside Neutron's existing execution and package model:

- physical applications remain normal Neutron applications;
- execution authority remains a Neutron `AppScope`;
- `.neutron` remains the package format;
- the kernel owner retains normal Neutron administrative authority;
- multi-tenancy adds tenant membership, grants, logical app discovery, allocation, lifecycle state, and tenant-scoped browser state.

The repository does not define higher-level product objects. External systems may map their own terminology onto these primitives without changing the kernel model.

For the file-level divergence policy, see [UPSTREAM.md](../UPSTREAM.md).

## 2. Branch and compatibility model

`dev` is the integration base for version work in this repository. `version-0.0.1` is developed against `dev` and is intended to merge back into it.

Current upstream Neutron `main` is a separate reference. It is used to answer a different question: how much of each upstream-derived file can remain identical to Neutron?

Those two comparisons should not be confused:

```text
version branch -> dev
    repository integration relationship

version branch -> upstream Neutron main
    compatibility and conflict-minimization relationship
```

## 3. Terminology

### Tenant

A principal that has joined the multi-tenant kernel. Tenant membership exists even when the tenant currently owns no app instances.

### Logical app

The tenant-facing application identity stored in the app catalog, for example:

```text
hello
```

A logical app describes what application a tenant can install/open. It is not itself an execution scope.

### Physical app instance

A real Neutron application identity compiled into the combined actor, for example:

```text
hello_001
hello_002
```

Each physical app instance has its own ordinary Neutron AppScope and therefore its own physical runtime identity.

For the current proof of concept, the physical app id and the allocated instance id are the same identifier.

### App pool

The set of physical app instances registered to one logical app.

### Grant

A persisted relationship from a tenant principal to a physical app-instance id. Grants are the tenant's execution authorization inventory.

### Allocation

The operation that finds or assigns one usable physical app instance from a logical app's pool to a tenant.

### Retirement

Permanent exclusion of a physical app instance from future allocation.

### Workspace and tile

Frontend views. Opening, closing, moving, or duplicating tiles does not allocate additional physical app instances.

## 4. Execution model

Neutron already compiles installed applications into one combined Internet Computer actor. `multitenancy-neutron` keeps that architecture.

A physical app instance is therefore not a container or a second canister. It is an ordinary Neutron application identity inside the kernel actor with its own AppScope.

Conceptually:

```text
kernel canister
  |
  +-- kernel
  +-- hello_001   AppScope A
  +-- hello_002   AppScope B
  +-- demo_001    AppScope C
  +-- demo_002    AppScope D
```

A tenant receives a grant to exactly one of those physical identities. Existing Neutron capability and physical-name machinery then provides the execution boundary.

This is intentionally different from introducing a second logical authorization layer around application methods. Logical app ids are for catalog/allocation decisions. Physical AppScopes remain authoritative for execution.

## 5. Data model

The current implementation adds four kernel stable-memory roots.

### `tenants`

```text
principal -> [physical app_instance_id]
```

Responsibilities:

- record tenant membership;
- store exact physical grants;
- permit an empty grant list so membership is independent of installed apps.

A logical installation record is not duplicated here. Logical identity is derived through `app_instances`.

### `app_instances`

```text
physical app_instance_id -> logical app_id
```

Responsibilities:

- associate physical Neutron application identities with one logical catalog app;
- allow the allocator to determine whether a tenant already has an instance of a logical app;
- separate catalog identity from execution identity.

### `app_instance_lifecycle`

```text
physical app_instance_id -> retired
```

Responsibilities:

- persist permanent non-reuse state;
- prevent retired instances from being selected by allocation;
- keep lifecycle state independent from current tenant ownership.

### `app_catalog`

```text
logical app_id -> { name, description }
```

Responsibilities:

- provide tenant-facing logical application discovery;
- preserve catalog metadata independently of physical capacity;
- allow owner administration to inspect logical apps even when their pools are exhausted.

## 6. Allocation invariant

The central invariant is:

```text
(principal, logical app) -> zero or one usable physical app instance
```

Allocation must be persistent, idempotent, and deterministic.

### Existing allocation

Given a principal and logical app:

1. read the tenant's physical grants;
2. map each granted physical id through `app_instances`;
3. retain instances registered to the requested logical app;
4. reject unusable instances, including retired or no-longer-installed physical ids;
5. if historical state contains more than one candidate, choose deterministically.

The current deterministic tie-break is lexical physical id order.

### New allocation

When no usable existing allocation exists:

1. enumerate physical instances registered to the logical app;
2. require that the instance is currently installed;
3. require that it is not retired;
4. require that it is not assigned to another tenant;
5. choose the deterministic lowest candidate;
6. append that physical id to the caller's grants.

The allocator contains no `await` between candidate selection and grant mutation, so the lookup and write execute atomically within the canister message.

Repeating the same allocation returns the existing physical id rather than consuming a new pool slot.

## 7. Authorization model

There are two distinct authorization concepts.

### Owner authorization

The kernel's ordinary Neutron authorized-principal set continues to define administrative authority.

Owner operations include physical deployment and administrative catalog/pool operations. Multi-tenant membership must not weaken or replace this boundary.

### Tenant session authorization

A principal is session-authorized when either:

- it is a Neutron owner; or
- it has a tenant entry.

Tenant self-enrollment creates an empty tenant grant list. It does not add the caller to Neutron's owner authorization set.

### App authorization

For a non-owner tenant, a physical AppScope is authorized only when the exact physical app id is present in that principal's grants.

Conceptually:

```text
owner:
    all ordinary owner-authorized kernel/app operations

tenant:
    session APIs
    + exact granted physical AppScopes
    - owner administration
    - another tenant's AppScopes
```

Knowledge of a physical app-instance id is never sufficient authority.

## 8. Catalog visibility

The tenant-facing logical app catalog has two visibility cases.

An app is visible when:

1. the tenant already owns a usable physical instance of that logical app; or
2. at least one usable, unassigned physical pool instance is available.

The first rule ensures an installed logical app remains visible as `Open` even when every remaining physical slot has been allocated.

An unallocated tenant should not be offered an app whose pool has no available capacity.

## 9. Launcher behavior

The tenant launcher presents logical apps rather than the raw physical registry.

For each logical app:

```text
no allocation -> Install
allocation    -> Open
```

`Install` invokes the allocator. `Open` does not.

A tenant may open multiple workspace tiles for the same logical app. All such tiles use the same physical app instance because workspace tiles are views, not allocations.

### Registry-refresh race

Logical allocation state and the frontend's loaded physical app registry are obtained independently. Immediately after a successful allocation, the newly allocated physical app may not yet exist in the current frontend store.

The launcher therefore:

1. looks for the physical app in the current registry;
2. if absent, performs exactly one authoritative `getApps()` refresh;
3. retries the physical lookup;
4. fails visibly if the instance is still unavailable.

Do not replace this with sleeps, polling loops, or arbitrary retries.

## 10. App pools and publication

The current owner workflow can take an ordinary `.neutron` package and derive multiple physical package identities in memory.

For a logical app `hello`, capacity 4 currently produces identities such as:

```text
hello_001
hello_002
hello_003
hello_004
```

The process rewrites only identity-bearing package metadata for each physical clone, then compiles/deploys the resulting package batch through Neutron's normal compiler/deployment path.

After the deployment is committed, the logical catalog entry and physical-instance mappings are registered with the kernel.

A retained copy of the original logical package is stored at a repository-specific kernel asset path so additional capacity can later be derived from the same package.

Current path:

```text
/multitenancy-neutron/templates/<logical-app-id>.neutron
```

### Current limitation

The proof-of-concept app-pool publication path rejects application packages with dependencies. This is not a package-format restriction. Standard `.neutron` compatibility remains a requirement; the pool compiler path needs to be extended to reproduce dependency graphs safely for multiple physical identities.

## 11. Retirement lifecycle

Retirement is stronger than revocation.

### Revocation

Removes a physical app instance from a tenant's grants. A non-retired physical slot may become allocatable again.

### Retirement

Marks the physical app instance as permanently unusable and removes the tenant grant. The id must never be selected by future allocation.

Required lifecycle regression:

```text
allocate X
retire X
allocate the same logical app again
new allocation != X
```

This deployed regression is a known test gap for the current version branch.

## 12. Browser workspace isolation

Workspace state is browser-local but still tenant-sensitive.

Persistence keys are scoped by both the kernel canister and authenticated principal:

```text
neutron-kernel-workspaces-v2:<canisterId>:<principal>
```

On identity change, the active persistence scope changes before tenant workspace state is loaded.

The legacy unscoped key:

```text
neutron-kernel-workspaces-v2
```

must not be migrated into a scoped tenant workspace because a shared browser/origin may have previously been used by another principal.

Workspace persistence is best-effort local storage. It is not the source of allocation or authorization truth.

## 13. Persistence and upgrades

Stable-memory root names, field layouts, and stored identifier semantics become compatibility contracts once real deployments are expected to upgrade in place.

Current roots:

```text
tenants
app_instances
app_instance_lifecycle
app_catalog
```

Changing any of the following requires explicit migration once upgrade compatibility is promised:

- root names;
- v1 record/map layouts;
- meaning of physical ids;
- meaning of logical ids;
- relationships between grants and physical identities.

Generated actor wrappers and lock metadata must be regenerated through the normal Neutron toolchain after source/schema changes. They should not be hand-edited as a migration mechanism.

## 14. Package compatibility

`multitenancy-neutron` does not define a replacement application package format.

A standard upstream-compatible `.neutron` package must remain installable through the ordinary Neutron path. Multi-tenant pool functionality is layered around normal package preparation, compilation, deployment, and AppScope generation.

This requirement is important for two reasons:

1. the repository should inherit future Neutron application compatibility rather than maintain a forked ecosystem;
2. higher-level control planes should not need a special runtime package solely because the target host is multi-tenant.

## 15. Deployment topology

The tenant/allocation model is intentionally independent of deployment topology.

The current development helpers can describe one or more host nodes, but host/shard selection is infrastructure policy rather than part of the core tenant data model.

A future multi-host allocator may need capacity discovery and placement policy, but those concerns should not change the meaning of:

```text
principal
logical app
physical app instance
AppScope
grant
retirement
```

## 16. Upstream conflict minimization

The long-term maintenance goal is not merely working multi-tenancy. It is a small, reviewable delta from Neutron.

For every upstream-derived file changed by `multitenancy-neutron`:

1. compare it with current upstream Neutron;
2. restore upstream code exactly where no multi-tenant behavior is required;
3. move multi-tenant implementation into repository-owned modules where practical;
4. leave a small, explicit integration seam in the upstream-derived file;
5. protect the seam with focused tests.

The largest current conflict hotspots are:

```text
apps/kernel/backend/main.mo
apps/kernel/src/reducer/apps.ts
apps/kernel/src/reducer/auth.ts
apps/kernel/src/workspace/Launcher.tsx
apps/kernel/src/workspace/KernelTrayItem.tsx
apps/kernel/src/workspace/store.ts
```

See [UPSTREAM.md](../UPSTREAM.md) for the current classification and [TODO.md](../TODO.md) for the extraction plan.

## 17. Test invariants

The multi-tenant test suite must preserve all of the following:

- tenants can join without becoming owners;
- owners retain ordinary administrative authority;
- tenants cannot invoke owner-only deployment authority;
- repeated allocation of one logical app returns the same physical instance;
- different logical apps allocate independently;
- different tenants receive distinct physical instances when using the same logical app pool;
- tenant grants do not overlap for an allocated physical instance;
- allocation survives actor/client recreation;
- the owning tenant can call its physical AppScope;
- another tenant cannot call that AppScope;
- launcher `Install -> Open` does not allocate twice;
- reopening and browser reload preserve the same physical allocation;
- workspace persistence does not cross principal boundaries;
- retired physical instances are never reused.

Ordinary upstream Neutron package, owner, compiler, and runtime tests remain additional compatibility gates rather than being replaced by these tests.

## 18. Current architectural cleanup target

The current branch proves the behavior but still places too much multi-tenant implementation directly inside upstream-derived files.

The intended cleanup shape is:

```text
upstream-derived Neutron code
        |
        +-- small explicit integration seams
                |
                v
multitenancy-neutron-owned modules
        |
        +-- tenant/session logic
        +-- catalog + pool logic
        +-- allocation + lifecycle logic
        +-- tenant UI variants
        +-- focused persistence helpers
```

This separation is the main architectural objective before `version-0.0.1` is merged into `dev`.
