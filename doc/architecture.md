# Plasmon Architecture

## 1. Purpose

Plasmon is a multi-user personal application cloud built on the **Neutron** kernel/runtime.

Its product model is inspired by Sandstorm grains: applications define small, independently owned and shared units of data rather than treating the entire application as one user object. Plasmon calls those units **Atoms**.

Neutron provides the execution, persistence, authorization, and application-scope substrate. Plasmon defines the higher-level application, object, ownership, sharing, and workspace model above it.

A critical architectural distinction is:

```text
Plasmon Atom != Neutron app_instance
```

A Neutron `app_instance` / `AppScope` is a physical execution and authorization primitive. An Atom is a porter-defined user object or grain. Phase 9 proves the physical substrate; Phase 10 defines the first real Atom model.

## 2. Terminology and naming convention

### 2.1 Product model

```text
Plasmon
└── Element
    ├── Isotope
    └── Atoms created with the Element
```

- **Plasmon** — the platform/personal application cloud.
- **Element** — a logical application/package exposed to users, such as Notepad, Wekan, or Git.
- **Isotope** — a particular version/build/runtime profile of an Element.
- **Atom** — a porter-defined isolated unit created with an Element, usually the smallest independently owned/shared data object that makes sense for that application.
- **Neutron** — the kernel/runtime substrate.
- **Tenant** — a user/principal using Plasmon.
- **Grant** — authorization relating a principal to a Neutron execution scope or, in future product APIs, to a specific Atom capability.
- **Shard** — one Neutron canister participating in a Plasmon deployment.

An Atom is modeled after a **Sandstorm grain**. Sandstorm's developer handbook describes a grain as a discrete collection of data whose granularity is chosen by the person porting the app, with the rule of thumb that it should usually be the smallest useful **unit of sharing**.

Examples include:

```text
Element                    Atom / grain
-------------------------  -------------------------
document editor            one document
spreadsheet editor         one spreadsheet
Wekan / kanban             one board
Git application            one repository
blogging application       one blog
chat application           one chat room
mail application           one mailbox
notebook application       one notebook
photo gallery              one photo album
image editor               one image
```

The porter chooses the boundary. Plasmon does not impose one universal Atom granularity.

Sandstorm references:

- https://docs.sandstorm.io/en/latest/developing/handbook/
- https://sandstorm.io/how-it-works
- https://docs.sandstorm.io/en/latest/vagrant-spk/packaging-tutorial/

### 2.2 Installing an Element is not creating an Atom

Installing or making an Element available to a tenant and creating an Atom are separate operations.

For example:

```text
Tenant installs Notepad once
        ↓
Create document "Shopping list"
        ↓
Atom A

Create document "Project notes"
        ↓
Atom B

Create document "Meeting notes"
        ↓
Atom C
```

One installed Element may therefore create zero, one, or many Atoms.

This mirrors Sandstorm's model where a user installs an application and then creates multiple grains of that application.

### 2.3 Isotope relationship

An Atom is created using some Isotope of an Element.

Conceptually:

```text
Element: Notepad
├── Isotope: stable 1.0
│   ├── Atom: Shopping list
│   └── Atom: Project notes
└── Isotope: beta 1.1
    └── Atom: Beta-test document
```

The implementation does not yet maintain a complete first-class Isotope registry. Package/version/build metadata is currently the implementation-level precursor.

### 2.4 Implementation terminology

Generic Neutron production code should normally use:

```text
app
app_id
app_instance
app_instance_id
tenant
principal
grant
allocation
runtime
```

Plasmon-specific code and documentation may use:

```text
Element
Isotope
Atom
atom_id
porter
shard
```

Do **not** mechanically translate `Atom` to `app_instance`. The two concepts are intentionally distinct.

### 2.5 Stable-memory naming

The Phase 9 tenant memory was renamed before merge to the generic identity:

```text
memory id: tenants
source: memory/tenants/v1.mo
```

Because this identity has not yet shipped in the target branch, no compatibility migration is required for that rename.

Once a stable-memory identity ships, future identity changes require an explicit migration/compatibility plan.

## 3. Product object model versus execution substrate

The intended Plasmon object model looks like this:

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

The current Phase 9 Neutron substrate looks different:

```text
Neutron shard/canister
├── kernel
├── logical app: hello
│   ├── physical app_instance: hello_001
│   └── physical app_instance: hello_002
└── logical app: demo
    ├── physical app_instance: demo_001
    └── physical app_instance: demo_002
```

The `hello_001`-style identifiers above are **physical execution slots**, not Atoms. Hello has no meaningful porter-defined grain/object model yet.

Phase 9 intentionally proves physical allocation, persistence, and AppScope authorization before Plasmon defines the Atom layer.

## 4. Deployment topology

### 4.1 Default topology

The default production model is one shared Neutron canister:

```text
Internet Computer
└── Plasmon shared shard
    └── Neutron combined actor
        ├── kernel
        ├── hello_001
        ├── hello_002
        ├── notepad_001
        ├── notepad_002
        └── ...
```

These installed identities are Neutron physical app instances / AppScopes.

The system should add shards only when the current shard approaches practical limits.

### 4.2 Future topology

```text
Plasmon
├── shared shard A
│   ├── many tenants
│   └── many physical app instances
├── shared shard B
│   └── overflow execution capacity
└── dedicated shard
    └── future paid/high-demand tenant or workload
```

The product UX should eventually hide shard placement from normal tenants and from normal Atom operations.

## 5. Neutron execution model

Neutron statically assembles the kernel and installed application modules into one Motoko actor.

For each physical app identity, the compiler creates a distinct AppScope and generated wrapper surface.

Conceptually:

```text
logical Neutron app: notepad

physical execution instances:
notepad_001 → AppScope(notepad_001)
notepad_002 → AppScope(notepad_002)
notepad_003 → AppScope(notepad_003)
```

Physical app identities must therefore exist when the combined actor is compiled.

Adding physical execution capacity currently requires:

1. generating new physical app identities;
2. compiling a new combined actor containing them;
3. self-upgrading the Neutron canister;
4. registering the new physical instances in the logical app registry.

Neutron's current installed-app bound around 256 is treated as a tested product-scale limit, not an Internet Computer protocol limit. Raising it requires scale validation.

### 5.1 Atom mapping is not yet defined

Phase 9 does **not** decide how many Atoms map to one physical `app_instance` / AppScope.

Phase 10 must explicitly define the mapping.

The strongest Sandstorm-like candidate is:

```text
1 Atom ↔ 1 AppScope
```

because Sandstorm isolates each grain independently. However, that mapping has major implications for precompiled capacity, shard scale, creation latency, and upgrade mechanics, so it must be proven rather than assumed.

If Plasmon allows any other mapping, it must still preserve independent Atom ownership, sharing, persistence, and security boundaries.

## 6. Logical registries

Plasmon introduces logical state above physical Neutron app identities.

### 6.1 Element catalog

The current Element catalog stores logical metadata:

```text
app_id
name
description
```

Example:

```text
app_id: notepad
name: Notepad
description: Private personal notes
```

### 6.2 Physical app-instance registry

The current physical registry maps a physical Neutron app instance to its logical app:

```text
notepad_001 → notepad
notepad_002 → notepad
notepad_003 → notepad
```

This is **not the Atom registry**.

It exists to support physical execution allocation and capacity management.

### 6.3 Future Atom registry

Phase 10 should introduce the first real Atom identity model. At minimum, an Atom needs enough persistent identity to support:

```text
atom_id
logical Element / app_id
porter-defined object noun/type
owner principal
execution mapping
human title/name
lifecycle state
```

Future sharing metadata can then attach to the Atom boundary rather than to an entire Element.

### 6.4 Atomic physical-pool registration

The owner-only `kernel_app_pool_register` operation currently registers:

- logical `app_id`;
- display name;
- description;
- one or more physical `app_instance_ids`.

All physical instances are validated before registry mutation.

The registration call is intentionally performed after a successful Neutron deployment because the registry must not point at physical scopes that were never installed.

That creates a small split boundary: deployment may commit before registry registration. A future recovery/reconciliation path must handle this deterministically.

## 7. Tenant model

A tenant is identified by an Internet Computer principal.

Tenant membership is independent from Atom ownership and independent from physical app grants.

Conceptually, Phase 9 currently has:

```text
tenant principal
    ↓
persistent physical grant list
    ↓
Neutron app_instance IDs
```

Example:

```text
Alice principal
├── notepad_001
└── demo_002

Bob principal
└── notepad_002
```

This state proves the execution authorization substrate. Phase 10 must layer Atom ownership on top of it rather than relabeling these physical grants as Atoms.

## 8. Authorization

### 8.1 Owner authorization

Neutron owners retain global kernel authority.

Kernel/admin operations continue to use owner authorization.

Examples include:

- kernel install/update operations;
- logical pool registration;
- owner grant/revoke tooling;
- physical capacity administration.

### 8.2 Tenant session authorization

A tenant session is recognized when the caller is an owner or a registered tenant.

This allows a tenant with zero physical app grants and zero Atoms to enter Plasmon.

### 8.3 Physical AppScope authorization

For a non-kernel app method, the generated wrapper checks authorization against the exact physical AppScope.

Conceptually:

```text
caller Alice
scope notepad_001
→ allowed only if Alice has that physical grant

caller Alice
scope notepad_002
→ rejected if notepad_002 belongs to Bob
```

The frontend is not the security boundary. Launcher filtering improves UX, but backend AppScope authorization remains authoritative.

### 8.4 Future Atom authorization

Atom ownership/sharing must be scoped to the specific Atom.

Desired property:

```text
access to Atom A
!= access to every Atom of the same Element
```

For the Phase 10 Notepad proof, access to document A must not imply access to document B.

If Atom-to-AppScope mapping is 1:1, Neutron's exact AppScope authorization can directly enforce that boundary. If the mapping is not 1:1, Plasmon needs an equally strong Atom-specific capability/authorization layer.

## 9. Phase 9 physical allocation

Phase 9 allocation operates on logical apps, not on Atoms.

The caller requests:

```text
app_id = hello
```

The kernel selects a physical app instance that is:

- registered under that logical app;
- installed in the current Neutron actor;
- not retired;
- not assigned to another tenant.

The current allocator selects the lexicographically first qualifying physical instance.

Example:

```text
free physical instances: hello_001, hello_002

Alice requests hello
→ hello_001

Bob requests hello
→ hello_002
```

Phase 9 also enforces:

```text
(principal, logical app) -> zero or one physical app_instance
```

Repeated allocation returns the existing physical instance instead of consuming another physical slot.

This is an installation/execution-allocation invariant only. It must **not** be interpreted as:

```text
(principal, Element) -> exactly one Atom
```

That would conflict with the Sandstorm grain model.

## 10. Porter-defined Atom contract

The porter defines the Atom boundary for an Element.

### 10.1 Granularity metadata

Phase 10 should define metadata that allows a porter to declare the user-facing noun for one Atom.

Examples:

```text
Notepad     → document
Wekan       → board
Git         → repository
Notebook    → notebook
ImageEditor → image
```

Sandstorm packaging similarly lets an app package customize the noun shown when creating a new grain.

Plasmon should use porter metadata for UI such as:

```text
New document
New board
New repository
```

rather than hardcoding per-application behavior into the shell.

### 10.2 Atom identity

An Atom needs a stable identity distinct from:

- Tile ID;
- physical `app_instance_id` unless the mapping is explicitly 1:1;
- Element `app_id`;
- Isotope/version identity.

Closing a Tile must not delete the Atom. Reloading must not change its identity.

### 10.3 Atom lifecycle

The initial product lifecycle should support at least:

```text
create
list/discover
open
rename/title
delete/trash/retire
```

Future hooks may include:

```text
share
clone
import
export
migrate
change Isotope
```

without requiring all of those in Phase 10.

## 11. Phase 10 Notepad acceptance model

Phase 10 is the first phase that introduces real Atom semantics.

The acceptance Element is **Notepad**.

Porter declaration:

```text
Element: Notepad
Atom noun: document
```

Expected behavior:

```text
Tenant gets access to Notepad once

Create "Shopping list"
→ Atom A

Create "Project notes"
→ Atom B

Create "Meeting notes"
→ Atom C
```

Required invariants:

1. A, B, and C have distinct Atom identities.
2. Text stored in A does not appear in B or C.
3. Reload preserves all three Atom identities and contents.
4. Opening Atom A twice may create two Tiles pointing to Atom A.
5. Opening Atom B opens B, not another view of A.
6. Closing a Tile does not delete its Atom.
7. Another tenant cannot access A without an explicit future sharing grant.
8. The shell gets the noun `document` from porter metadata rather than hardcoding Notepad semantics.

Phase 10 must also settle how these document Atoms map onto Neutron AppScopes.

## 12. Physical retirement versus Atom lifecycle

Phase 9 currently supports retirement of physical app instances.

A retired physical app instance is permanently excluded from future physical allocation because it may contain tenant-specific stable state.

Safe substrate default:

```text
physical app_instance retired
→ revoke physical grant
→ mark physical slot retired
→ never assign that physical state to another tenant
```

This is not automatically the same thing as deleting an Atom.

Once the Atom layer exists, Plasmon must separately define:

- what deleting/trashing an Atom means;
- whether its physical execution scope can ever be securely reclaimed;
- retention/recovery semantics;
- whether a future reset/migration can prove safe physical reuse.

Implicit reuse of tenant data is prohibited.

## 13. Runtime Publish Element

### 13.1 Goal

Production publishing should happen from Plasmon itself rather than by editing a host-side JSON file and reinstalling the deployment.

Current owner flow:

```text
Plasmon Admin
└── Publish Element
    ↓
upload .neutron
    ↓
metadata + initial physical execution capacity
    ↓
one owner approval
    ↓
one Neutron self-upgrade
    ↓
logical app + physical pool registration
    ↓
available to tenants
```

The current UI/code may still contain legacy wording such as "Atom capacity". Until Phase 10 settles Atom-to-AppScope mapping, the architectural term is **physical execution capacity** or **app-instance capacity**.

### 13.2 Package fan-out

The uploaded `.neutron` package is decoded once.

The browser creates physical variants in memory by rewriting package identity metadata while sharing immutable module/web byte arrays.

For a logical package:

```text
id: notepad
```

with physical capacity `4`:

```text
notepad_001
notepad_002
notepad_003
notepad_004
```

These are physical app identities, not Atom IDs.

Identity-bearing package metadata rewritten for each physical variant includes:

- `neutron.json`;
- `schema.json` app identity metadata;
- `neutron.lock.json` app identity.

Large module and web payloads do not need to be copied byte-for-byte for each in-memory clone.

### 13.3 Approval and compilation ordering

Neutron's approval UI requires compilation metadata before approval can complete.

Therefore runtime publishing starts:

- batch compilation; and
- the owner approval request

concurrently.

After both complete successfully, the prepared package batch is deployed.

Sequentially waiting for approval before starting compilation creates a deadlock where the UI remains on `Compiling...`.

### 13.4 One deployment

All requested physical app instances are compiled as one prepared package batch and installed through one Neutron self-upgrade.

The intended cost model is:

```text
N new physical app instances
!= N canister upgrades

N physical instances
→ 1 combined actor compile
→ 1 self-upgrade
```

### 13.5 Dependency restriction

Initial runtime publishing rejects package dependencies.

Reason: logical package dependencies do not yet define physical tenant-aware dependency routing.

This must be designed before dependencies are allowed.

## 14. Physical capacity strategy

Physical execution capacity should be demand-driven.

Large speculative pools are undesirable because every installed physical AppScope contributes to the combined actor inventory and therefore affects future compile/upgrade work.

Current bootstrap target:

```text
initial physical instances per logical app: 4
```

Future Add Capacity flow:

```text
logical app notepad currently:
notepad_001 .. notepad_004

owner Add Capacity +4
        ↓
generate:
notepad_005 .. notepad_008
        ↓
batch compile
        ↓
one self-upgrade
        ↓
register only the new physical IDs
```

Automatic physical capacity expansion may later use low-water thresholds, but it should expand in batches rather than triggering a canister upgrade for every allocation.

How **Atom creation** consumes this physical capacity is deliberately deferred to Phase 10's Atom-to-AppScope mapping decision.

## 15. Isotopes

Isotope represents a version/build/runtime profile of an Element.

It is intentionally separate from Atom:

```text
Element = what application is this?
Isotope = which version/variant executes it?
Atom = which porter-defined user object/grain is this?
```

A future registry may model:

```text
Notepad
├── stable / version 1.4
└── beta / version 2.0-beta
```

Questions still to resolve:

- whether an Atom is pinned to one Isotope;
- in-place Atom upgrades versus migration;
- rollout channels;
- rollback;
- stable-memory compatibility;
- whether tenants can opt into beta Isotopes.

Until then, implementation code should use normal `version`, `build`, and `package` metadata.

## 16. Development bootstrap

Local development currently supports declarative bootstrap pools through:

```text
plasmon-app-pools.json
plasmon-capacity.ts
plasmon-bootstrap.ts
plasmon-provision.ts
```

The capacity generator materializes physical package identities and creates a generated deployment configuration.

This mechanism is useful for deterministic tests and initial local setup.

It is **not** the desired production publishing architecture and must not be described as pre-creating product Atoms.

Production should preserve runtime-published Elements, future Atom state, and execution mappings across subsequent Neutron/Plasmon upgrades.

## 17. Build and browser-compiler performance

The current developer and runtime publishing paths expose two related performance issues.

### 17.1 Kernel development build cost

Frontend, kernel, compiler, and packaging work are currently coupled tightly enough that frontend-only edits require an expensive full package/deploy cycle.

Required direction:

```text
frontend-only edit
→ local dev server
→ HMR/watch
→ no canister upgrade
```

The full package/deploy path should remain the final integration test, not the CSS editing loop.

### 17.2 Runtime publishing module fetches

The browser compiler retrieves many existing Motoko modules using content-addressed paths such as:

```text
/mo/<content-hash>.mo
```

These modules are natural immutable-cache candidates.

Future publishing should reuse modules already cached by hash instead of redownloading unchanged content for every Element or physical-capacity operation.

### 17.3 Build cache

The kernel build/package pipeline should gain explicit incremental cache boundaries.

Potential cache units include:

- frontend bundle;
- individual Motoko source/module inputs;
- generated assembly inputs;
- compiler output where all relevant inputs are unchanged;
- packaged static assets.

Cache correctness and invalidation must be documented and tested.

## 18. Sharding

A single shared canister remains the default.

Sharding becomes necessary only when practical constraints justify it, including:

- installed physical app count;
- compile time;
- Wasm size;
- canister memory;
- cycles;
- deployment latency;
- workload isolation.

Future Plasmon routing should map Element and Atom operations to the correct shard without exposing that complexity in normal UX.

Atom identity should therefore not depend on a user-visible shard name.

## 19. Production ownership

Local development currently uses deterministic test identities.

That mechanism is only for PocketIC/E2E work.

Production requires:

- explicit first-owner bootstrap;
- safe owner recovery;
- add/revoke owner administration;
- separation between normal Plasmon administration and low-level Neutron administration.

## 20. Security invariants

The following invariants are architectural requirements:

1. Kernel owner authority cannot be acquired merely by becoming a tenant.
2. Tenant membership does not imply access to every installed app.
3. Phase 9 physical app calls require the exact granted AppScope.
4. One allocated physical app instance may belong to at most one tenant under the Phase 9 substrate model.
5. Retired physical app instances are not implicitly reassigned.
6. Tenant A cannot invoke Tenant B's granted physical AppScope.
7. Logical Element metadata never substitutes for physical AppScope authorization.
8. Publishing and physical-capacity operations remain owner-only.
9. Registry state must not claim a physical app instance exists unless its Neutron scope is committed.
10. Frontend filtering must never be relied on as the authorization boundary.
11. Atom identity is distinct from Tile identity.
12. Atom identity is distinct from physical `app_instance_id` unless an explicit mapping rule defines them as 1:1.
13. Access to one Atom must not imply access to unrelated Atoms of the same Element.
14. Porter-defined Atom granularity must be explicit and stable enough for ownership/sharing semantics.

## 21. Architectural direction

The intended long-term model is:

```text
Plasmon owner publishes an Element
        ↓
Neutron provides physical execution capacity
        ↓
tenant installs/gets access to the Element
        ↓
porter-defined Create action creates Atoms
        ↓
Atoms are independently owned/opened/shared
        ↓
physical execution capacity expands as required
        ↓
Element upgrades become Isotopes
        ↓
shared shards scale horizontally when necessary
```

Phase sequence:

```text
Phase 9
physical tenant allocation + AppScope authorization substrate
        ↓
Phase 10
porter-defined Atom contract + Notepad proof
(document = Atom)
        ↓
later phases
sharing, cloning/import/export, Isotope migration, cross-shard placement
```

Neutron remains the runtime substrate. Plasmon adds logical application identity, porter-defined object/grain identity, ownership, sharing, workspace semantics, capacity management, and product UX above it.
