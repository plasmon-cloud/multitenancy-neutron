# Plasmon

Plasmon is a Sandstorm-inspired personal application cloud built on the **Neutron** kernel/runtime for the Internet Computer.

The project uses Neutron's isolated application scopes as an execution substrate while Plasmon defines the user-facing application, object, ownership, and sharing model.

## Product terminology

| Product term | Meaning | Implementation convention |
| --- | --- | --- |
| **Plasmon** | The personal application cloud/platform | `plasmon` |
| **Element** | A logical application/package visible to users | `app`, `app_id` |
| **Isotope** | A variant, version, build, or runtime profile of an Element | `version`, `build`, `package` |
| **Atom** | A porter-defined isolated unit created with an Element: usually the smallest independently owned/shared data object that makes sense for that app | Plasmon `atom`, `atom_id` once defined; **not** synonymous with Neutron `app_instance` |
| **Neutron** | The kernel/runtime substrate | Neutron's existing kernel/runtime names |
| **Tenant** | A user/principal using Plasmon | `tenant`, `principal` |
| **Grant** | Authorization from a tenant to a physical Neutron execution scope | `grant` |
| **Shard** | One Neutron canister participating in a Plasmon deployment | `shard`, node/canister identifiers |

Product terminology belongs in user-facing Plasmon UX and documentation. Internal Neutron implementation code should normally use generic names such as `app`, `app_instance`, `tenant`, `grant`, and `shard`.

### Atom means Sandstorm-style grain

Plasmon's **Atom** is modeled after a Sandstorm **grain**.

A grain is not normally "one copy of the whole app" as a user concept. Sandstorm describes a grain as a discrete collection of data whose granularity is chosen by the person porting the app. Its rule of thumb is the **unit of sharing**: the smallest thing a user would reasonably want to own or share independently.

Examples from Sandstorm include:

- a document in a document editor;
- a spreadsheet in a spreadsheet editor;
- a Wekan board;
- a Git repository;
- a blog;
- a chat room;
- a mailbox;
- a notebook;
- a photo album or, for an image editor, a single image.

For Plasmon, the **porter defines what an Atom is for an Element**. A Notepad porter can define one document as one Atom. A kanban porter can define one board as one Atom. A Git application can define one repository as one Atom.

Installing or making an Element available to a tenant is therefore **not the same operation as creating an Atom**. One installed Element may create many Atoms.

Sandstorm references:

- [What makes a good Sandstorm App?](https://docs.sandstorm.io/en/latest/developing/handbook/)
- [How Sandstorm Works: Containerize data, not services](https://sandstorm.io/how-it-works)
- [Packaging tutorial](https://docs.sandstorm.io/en/latest/vagrant-spk/packaging-tutorial/)

### Neutron implementation naming

Neutron production code remains product-agnostic. Product terminology such as **Plasmon**, **Element**, **Atom**, and **Isotope** belongs in Plasmon UX, documentation, and explicitly Plasmon-specific integration tooling.

Generic Neutron implementation code should use names such as:

```text
app
app_id
app_instance
app_instance_id
tenant
grant
allocation
runtime
```

A Neutron `app_instance` / `AppScope` is an execution and authorization primitive. It is **not automatically an Atom**. Phase 10 will define how porter-declared Atoms map onto Neutron execution scopes.

The Phase 9 tenant memory is named generically as `memory/tenants/v1.mo` before merge. Once a stable-memory identity ships, future identity changes require an explicit compatibility/migration plan.

## Product model versus execution substrate

The intended product model looks like this:

```text
Plasmon
├── Element: Notepad
│   ├── Atom: "Shopping list"       (document)
│   ├── Atom: "Project notes"       (document)
│   └── Atom: "Meeting 2026-08-09"  (document)
├── Element: Wekan
│   ├── Atom: "Home remodel"        (board)
│   └── Atom: "Release plan"        (board)
└── Element: Git
    └── Atom: "my-project"           (repository)
```

Those Atom boundaries are chosen by each Element's porter, not globally by Plasmon.

The current Phase 9 execution substrate is different:

```text
Neutron shard/canister
├── kernel
├── logical app: hello
│   ├── physical app_instance: hello_001 → tenant A
│   └── physical app_instance: hello_002 → tenant B
└── logical app: demo
    ├── physical app_instance: demo_001
    └── physical app_instance: demo_002
```

Phase 9 intentionally proves physical allocation, persistence, and AppScope authorization first. The `hello_001`-style physical IDs above should **not** be described as Atoms. Hello has no meaningful porter-defined grain/object model yet.

The current implementation provides:

- persistent tenant membership and grants;
- logical Element catalog metadata;
- logical app → physical app-instance registry;
- self-service tenant physical app-instance allocation;
- non-reusable retired physical app instances;
- tenant workspace isolation;
- owner-only kernel administration;
- tenant launcher filtering;
- runtime browser publishing of dependency-free `.neutron` packages;
- batch compilation and a single self-upgrade for multiple physical app instances;
- local development bootstrap generation.

See [`doc/architecture.md`](doc/architecture.md) for the detailed implementation model. Atom semantics in that document must remain consistent with the porter-defined model above as Phase 10 lands.

### Phase 9 status

Phase 9 implements the first tenant logical-app installation/allocation path. It validates:

- a tenant sees a logical app as installable before physical allocation;
- Install allocates one physical app instance for that tenant + logical app;
- repeated Install returns the same physical app instance;
- the launcher changes from Install to Open;
- opening the app repeatedly reuses that physical instance;
- multiple workspace Tiles can reference the same instance;
- browser reload preserves the installation mapping;
- exact physical AppScope authorization prevents cross-tenant access.

This is an **installation/execution allocation invariant**, not the final Atom model:

```text
(principal, logical app) -> zero or one physical app_instance
```

Phase 9 does not define Atom identity, Atom creation, or the porter contract for Atom granularity.

### Phase 10 direction: porter-defined Atoms

Phase 10 will introduce the first real Atom model using a Notepad Element.

The acceptance model is:

```text
Install / make Notepad available
        ↓
Create document "A"
        ↓
Atom A

Create document "B"
        ↓
Atom B

Create document "C"
        ↓
Atom C
```

Each document is a distinct Atom even though all three come from the same Notepad Element.

Phase 10 must define at least:

- how a porter declares the Atom noun/granularity for an Element;
- how an Element requests creation of a new Atom;
- stable Atom identity independent from incidental UI Tiles;
- Atom ownership and sharing metadata;
- Atom create/open/delete lifecycle;
- how an Atom maps to Neutron `app_instance` / `AppScope` isolation;
- whether the mapping is always 1:1 or is an explicit porter/runtime policy;
- how Element/Isotope upgrades apply to existing Atoms.

The Sandstorm design target is that the Atom is the isolated independently shareable object, not merely an app-launch record.

## Runtime publishing

The owner can publish an Element from a normal `.neutron` package.

The current Phase 9 flow is:

```text
upload logical .neutron package
        ↓
validate package and disclosures
        ↓
choose initial physical app-instance capacity
        ↓
decode package once
        ↓
fan out physical app identities in memory
        ↓
prepare all physical packages
        ↓
compile batch + request owner approval concurrently
        ↓
one Neutron self-upgrade
        ↓
register logical Element + physical app instances
        ↓
Element becomes available to tenants
```

For an Element with logical ID `notes` and physical capacity `4`, current development IDs look like:

```text
notes_001
notes_002
notes_003
notes_004
```

These are **physical Neutron app-instance IDs**, not automatically four Notes Atoms. The distinction matters once one tenant can create multiple porter-defined Atoms from the same Element.

The current recommended/default physical pool capacity is **4**. Capacity should be demand-driven and expanded in batches rather than preallocating large pools. Phase 10 may revise how physical capacity relates to Atom creation after the Atom-to-AppScope mapping is defined.

### Current publishing limitation

Initial runtime publishing rejects packages with dependencies.

A dependency such as `notes → database` cannot be copied blindly because Plasmon needs an explicit tenant- and Atom-aware mapping policy: for example, whether a Notes Atom depends on a per-Atom database scope, a tenant-shared service, or a globally shared service.

Dependency-aware publishing is deferred until that model is defined.

## Tenant installation and physical allocation

In Phase 9, a tenant requests a logical Element, not a specific physical app instance.

The kernel selects an installed, registered, non-retired, unassigned physical app instance and grants it to that tenant.

Example:

```text
Tenant A installs "hello"
→ kernel assigns hello_001

Tenant B installs "hello"
→ kernel assigns hello_002
```

A tenant's app call is authorized only when the caller owns the exact physical AppScope. Cross-tenant physical app-instance calls are rejected even when both instances belong to the same logical Element.

Repeated Install requests return the existing physical instance rather than allocating another one. Opening an installed app is a workspace operation only: it can create multiple Tiles, but those Tiles continue to reference the same physical app instance.

Phase 10 will separate this installation/execution concern from Atom creation. For Notepad, opening or installing Notepad must not imply that the tenant has only one document; creating each new document creates a new Atom.

## Retirement and deletion

Physical Neutron app instances are intentionally not recycled after retirement in the current implementation because they may contain tenant-specific stable state. Reassigning one to another principal would risk data leakage and authorization mistakes.

Atom deletion is a separate product-level lifecycle question. Phase 10 must define what deleting a document Atom means for its Atom identity, storage, sharing state, and underlying execution scope.

## Local development

The Plasmon local environment uses PocketIC through Neutron's deployment tooling.

### Start the local deployment

Terminal 1:

```bash
npm run plasmon:serve
```

### Package and deploy changed kernel/backend/frontend code

Terminal 2:

```bash
npm --workspace neutron-kernel run package
npm run plasmon:deploy
```

A separate `neutron-kernel build` step is intentionally **not** part of the Plasmon workflow because it currently costs approximately the same as `package`.

After a redeploy, refresh already-open browser pages so they load the newly deployed frontend chunks.

### Check status

```bash
npm run plasmon:status
```

### Run the focused tenant isolation test

```bash
npm run plasmon:test
```

## Local identities

The local PocketIC deployment uses deterministic test identities.

Current manual-development convention:

```text
seed 2 → owner
seed 3 → tenant A
seed 4 → tenant B
```

The local-only browser test hook can switch identity. For example, the normal manual tenant view is:

```js
await window.__NEUTRON_PLAYWRIGHT_LOGIN_AS__(3)
```

Automated tests that mutate tenant grants should use dedicated test identities rather than assuming a manual-development tenant is pristine, and they should clean their grants on both success and failure.

Production ownership must not depend on these numeric development seeds.

## Development bootstrap

The following files support deterministic local bootstrap and physical capacity generation:

```text
plasmon-app-pools.json
plasmon-shards.json
plasmon-base.ndeploy.json
plasmon-capacity.ts
plasmon-provision.ts
plasmon-bootstrap.ts
plasmon-tenant-admin.ts
plasmon-app-admin.ts
```

Generated deployment/configuration artifacts include:

```text
plasmon.ndeploy.json
.plasmon-generated/
```

These generated artifacts should not be treated as source files.

`plasmon-app-pools.json` is a **development/bootstrap mechanism**. It is not intended to become the production source of truth for published Elements or Atoms.

The production direction is:

```text
initial Plasmon deployment
        ↓
owner publishes Element in browser
        ↓
porter-defined Atom contract creates user objects
        ↓
Neutron/Plasmon upgrades preserve Elements + Atom identities/data
        ↓
physical execution capacity expands as required
```

## Build and frontend workflow

The current Neutron kernel pipeline is too expensive for frequent frontend-only iteration. At present, `TSX`/CSS changes require packaging and deployment to see the certified frontend.

This is a known high-priority development issue.

Planned work in [`TODO.md`](TODO.md) includes:

- local frontend watch/HMR against an existing PocketIC canister;
- incremental/build caching for the kernel pipeline;
- browser/compiler caching for content-addressed Motoko modules;
- reduced redundant network/preflight traffic;
- stale frontend chunk recovery after deployments.

Until that work lands:

- use focused tests/static inspection when a live deployment is unnecessary;
- use `package → plasmon:deploy` once when a live frontend/backend change must be tested;
- do not run a separate kernel `build` merely as a sanity check.

## Security model

Core Phase 9 security rules:

1. Neutron owners retain global kernel authority.
2. A tenant session is recognized independently from app ownership.
3. A non-owner app method is authorized against the exact physical AppScope.
4. One physical app instance belongs to at most one tenant under the current allocation model.
5. Retired physical app instances cannot be allocated.
6. Tenant A cannot invoke Tenant B's physical app instance.
7. Kernel install/admin operations remain owner-only.
8. Frontend filtering is convenience; backend authorization is the security boundary.

Phase 10 extends this with Atom ownership/sharing/isolation rules. The goal inherited from Sandstorm is that compromise of one Atom should not implicitly grant access to unrelated Atoms.

## Sharding direction

One shared canister is the default deployment model.

Additional shards should be introduced only when a canister approaches a practical capacity, compilation, memory, cycle, or installed-app limit.

Future placement policy can support:

- many free/shared tenants per canister;
- batched physical execution-capacity expansion;
- dedicated canisters/shards for paid tenants or high-demand workloads.

The frontend should eventually present one Plasmon environment even when a tenant's Atoms span multiple shards.

## Repository direction

Plasmon is being developed as a focused layer on top of Neutron rather than by replacing Neutron's internal vocabulary everywhere.

That separation is intentional:

```text
Product UX/docs:
Element / Isotope / Atom / Plasmon

Plasmon object model:
Atom = porter-defined independently owned/shareable unit

Neutron implementation:
app / version / app_instance / tenant / grant / shard

Runtime:
Neutron
```

An `app_instance` is a Neutron execution primitive. An Atom is a Plasmon object-model primitive. Phase 10 defines their relationship rather than assuming they are the same thing.

See [`TODO.md`](TODO.md) for current work and [`doc/architecture.md`](doc/architecture.md) for the detailed architecture.
