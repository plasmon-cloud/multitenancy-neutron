# multitenancy-neutron

`multitenancy-neutron` is a backwards-compatible extension of Neutron that adds generic multi-tenant application allocation and isolation while preserving Neutron's existing package and runtime model.

The repository intentionally uses Neutron terminology. Higher-level products can build their own user-facing models on top of these primitives without changing the runtime's concepts or package format.

## Status

`version-0.0.1` is the current version branch.

- `dev` is the integration base and eventual merge target for version work in this repository.
- Upstream Neutron `main` is a separate compatibility reference used to minimize divergence from the original project.
- `version-0.0.1` should remain mergeable into `dev` while upstream-derived files are kept as close to current Neutron as practical.

See [UPSTREAM.md](UPSTREAM.md) for the file-by-file divergence policy and [doc/architecture.md](doc/architecture.md) for the runtime model.

## Core model

A tenant is identified by an Internet Computer principal. Applications have two identities:

- **logical app** — the tenant-facing application identity, such as `hello`;
- **physical app instance** — an ordinary Neutron app identity and AppScope, such as `hello_001`.

The central allocation invariant is:

```text
(principal, logical app) -> zero or one usable physical app instance
```

Allocation is persistent and idempotent. Repeating allocation for the same principal and logical app returns the existing usable physical instance instead of consuming another pool slot.

A logical app may have a pool of physically isolated app instances. Different tenants can therefore use the same logical app while executing inside distinct Neutron AppScopes.

## Security model

`multitenancy-neutron` extends Neutron authorization without weakening owner authority or AppScope isolation.

- The kernel owner retains normal Neutron administrative authority.
- A tenant session is not an owner session.
- Tenant self-enrollment creates tenant membership only.
- A tenant may use only physical app instances explicitly granted to that principal.
- Knowing another tenant's physical app-instance id does not grant access to its AppScope.
- Physical deployment, catalog administration, and pool administration remain owner-controlled.
- Retired physical app instances are permanently excluded from future allocation.

The physical Neutron AppScope remains the execution security boundary.

## Persistence

The current multi-tenant state adds four stable-memory roots to the kernel:

```text
tenants
app_instances
app_instance_lifecycle
app_catalog
```

Their current roles are:

| Root | Mapping | Purpose |
| --- | --- | --- |
| `tenants` | principal -> physical app-instance ids | Tenant membership and grants |
| `app_instances` | physical app-instance id -> logical app id | Logical-to-physical relationship |
| `app_instance_lifecycle` | physical app-instance id -> retired flag | Permanent non-reuse state |
| `app_catalog` | logical app id -> metadata | Tenant-visible application catalog |

These identities and layouts are upgrade-sensitive once compatibility with deployed state is promised. See [doc/architecture.md](doc/architecture.md#persistence-and-upgrades).

Browser workspace persistence is also tenant-scoped:

```text
neutron-kernel-workspaces-v2:<canisterId>:<principal>
```

The legacy unscoped workspace key must not be migrated into a tenant-scoped workspace because it may contain another principal's browser state.

## Neutron compatibility

A primary goal is that an ordinary upstream-compatible `.neutron` package remains an ordinary `.neutron` package here.

`multitenancy-neutron` does **not** define a new package format. Pool publication creates multiple physical Neutron app identities from a normal package while keeping the package/compiler/runtime contracts as close to upstream as possible.

The current app-pool publishing prototype does not support application dependencies. That is a limitation of the pool-publishing path, not a change to the `.neutron` package format.

## Local development

Install dependencies using the normal Neutron development environment, then use the repository-specific helpers for the local multi-tenant deployment:

```bash
npm run multitenancy-neutron:generate
npm run multitenancy-neutron:deploy
npm run multitenancy-neutron:status
npm run multitenancy-neutron:test
```

`multitenancy-neutron:generate` creates local physical app-instance fixtures and a generated deployment file from:

```text
multitenancy-neutron-app-pools.json
multitenancy-neutron-base.ndeploy.json
multitenancy-neutron-shards.json
```

Generated output is written beneath `.multitenancy-neutron-generated/` and to `multitenancy-neutron.ndeploy.json`; both are ignored by Git.

Administrative development helpers are available as:

```text
multitenancy-neutron-app-admin.ts
multitenancy-neutron-tenant-admin.ts
multitenancy-neutron-bootstrap.ts
multitenancy-neutron-capacity.ts
multitenancy-neutron-provision.ts
```

These are development/control-plane helpers around the generic kernel APIs. They are not part of the tenant execution model.

## Validation

The important behavioral gates are:

```bash
npm --workspace neutron-kernel run package
npm --workspace neutron-kernel test
npm run multitenancy-neutron:deploy
npm run multitenancy-neutron:test
```

The multi-tenant E2E coverage protects, among other things:

- tenant self-enrollment without owner privilege;
- owner-only physical deployment authority;
- idempotent allocation;
- independent allocation of different logical apps;
- distinct physical allocations for different tenants;
- persistence across actor/client recreation;
- direct access to the owning physical AppScope;
- rejection of cross-tenant physical AppScope access;
- launcher `Install -> Open` behavior using the same physical app instance after reopen/reload.

A deployed retirement/non-reuse regression test is still required; see [TODO.md](TODO.md).

## Repository documentation

- [Architecture](doc/architecture.md) — runtime, authorization, allocation, persistence, and compatibility model.
- [TODO](TODO.md) — current cleanup and version roadmap.
- [Upstream divergence notes](UPSTREAM.md) — why this branch differs from Neutron and how to minimize those differences.

## Development rule

When changing an upstream-derived Neutron file, first ask whether the same behavior can live in a `multitenancy-neutron`-owned module with only a small integration seam in the upstream file. Generated artifacts and lock files should be regenerated by their owning tools rather than hand-edited.
