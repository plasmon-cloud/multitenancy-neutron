# multitenancy-neutron

`multitenancy-neutron` is a backwards-compatible extension of Neutron that adds generic multi-tenant application allocation and isolation while preserving Neutron's existing package and runtime model.

The repository intentionally uses Neutron terminology. Higher-level products can build their own user-facing models on top of these primitives without changing the runtime's concepts or package format.

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

The multi-tenant state adds four stable-memory roots to the kernel:

```text
tenants
app_instances
app_instance_lifecycle
app_catalog
```

Their roles are:

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

## Testing

The repository has separate test scopes so normal development does not require compiling and testing every bundled application.

| Command | Scope |
| --- | --- |
| `npm test` | Fast core gate. Runs the test suites for `packages/*` plus `neutron-kernel`. |
| `npm run test:core` | Explicit name for the same fast core gate. |
| `npm run test:apps` | Runs every app workspace's default test. Apps without a default test are packaged so their validation/build path is still exercised. |
| `npm run test:support` | Runs support-workspace tests such as Dispenser, repository, and update-source. |
| `npm run test:extras` | Runs specialized named test suites not represented solely by a workspace's default `test` command. |
| `npm run test:release` | Runs root typechecking, security validation, manifest validation, and packaging. |
| `npm run test:e2e:upstream` | Runs ordinary Neutron Playwright coverage, excluding the multi-tenant deployment-specific cases. |
| `npm run test:e2e:multitenancy` | Runs all Playwright tests whose names begin with `multitenancy-neutron`. |
| `npm run test:e2e:all:fresh` | Starts and owns the required PocketIC environments, runs both E2E groups, and shuts down the processes it started. |
| `npm run test:all` | Full repository gate: core, apps, release checks, support, specialized tests, and all E2E coverage. |

`npm test` intentionally does **not** compile/package every bundled application and does not run Playwright. It does include `npm --workspace neutron-kernel test`, which runs the Kernel's normal Bun tests and Motoko test runner.

The full application suite may require application-specific development tools that are not needed by the fast core gate. For example, the VFS ABI suite requires the external Motoko/Candid command-line tools used by that application.

Some security and packaging tests intentionally print red rejection diagnostics while testing unsafe input. A red diagnostic is not a failure when the enclosing test reports success.

The important multi-tenant behavioral coverage remains part of the E2E group and protects tenant isolation, owner separation, idempotent allocation, persistence, physical AppScope authorization, and launcher `Install -> Open` behavior.

Production qualification evidence such as `neutron-kernel certified-assets:qualify` remains a separate release-evidence activity. It is not silently treated as an ordinary test by `test:all`.

## Repository documentation

- [Architecture](doc/architecture.md) — runtime, authorization, allocation, persistence, and compatibility model.
- [TODO](TODO.md) — current cleanup roadmap.
- [Upstream divergence notes](UPSTREAM.md) — why this repository differs from Neutron and how to minimize those differences.

## Development rule

When changing an upstream-derived Neutron file, first ask whether the same behavior can live in a `multitenancy-neutron`-owned module with only a small integration seam in the upstream file. Generated artifacts and lock files should be regenerated by their owning tools rather than hand-edited.
