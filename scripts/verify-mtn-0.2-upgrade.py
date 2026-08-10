#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "origin/version-0.1.0"


def git_show(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{BASE}:{path}"],
        cwd=ROOT,
        text=True,
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


old_manifest = json.loads(git_show("apps/kernel/neutron.json"))
new_manifest = json.loads((ROOT / "apps/kernel/neutron.json").read_text())
old_lock = json.loads(git_show("apps/kernel/neutron.lock.json"))
new_lock = json.loads((ROOT / "apps/kernel/neutron.lock.json").read_text())

# The entire pre-0.2 stable-memory catalog must retain its schema definitions.
for root, definition in old_manifest["memory"].items():
    require(root in new_manifest["memory"], f"missing existing memory root: {root}")
    require(
        new_manifest["memory"][root] == definition,
        f"existing memory manifest changed: {root}",
    )

# The old initializer contract is preserved in order; 0.2 only adds the three
# new stable roots before the non-memory deployment arguments.
authorization_init_args = [
    "memory_authorization_grants",
    "memory_authorization_resource_epochs",
    "memory_authorization_audit",
]
filtered_new_init = [
    value for value in new_manifest["init_arg"]
    if value not in authorization_init_args
]
require(
    filtered_new_init == old_manifest["init_arg"],
    "0.1 initializer argument order/identity changed",
)
for name in authorization_init_args:
    require(name in new_manifest["init_arg"], f"missing new init arg: {name}")

expected_new_roots = {
    "authorization_grants": "memory/authorization_grants/v1.mo",
    "authorization_resource_epochs": "memory/authorization_resource_epochs/v1.mo",
    "authorization_audit": "memory/authorization_audit/v1.mo",
}
for root, source in expected_new_roots.items():
    require(root in new_manifest["memory"], f"missing authorization root: {root}")
    definition = new_manifest["memory"][root]
    require(definition.get("version") == 1, f"{root}: expected version 1")
    require(definition.get("migrations") == [], f"{root}: unexpected migration")
    require(
        definition.get("schemas", {}).get("1", {}).get("src") == source,
        f"{root}: unexpected schema source",
    )

# Packaging must keep every existing lock entry exactly unchanged. This proves
# the compiler still sees the old persistence schemas as the same contracts.
for root, definition in old_lock["memory"].items():
    require(root in new_lock["memory"], f"lock lost existing root: {root}")
    require(
        new_lock["memory"][root] == definition,
        f"existing lock/schema identity changed: {root}",
    )
for root in expected_new_roots:
    require(root in new_lock["memory"], f"lock missing authorization root: {root}")
    require(
        "1" in new_lock["memory"][root].get("schemas", {}),
        f"lock missing {root} v1 schema",
    )
    require(
        new_lock["memory"][root].get("migrations", {}) == {},
        f"lock contains unexpected {root} migration",
    )

# Protect the persistence-sensitive 0.1 data model and allocator source from
# accidental edits while adding authorization roots.
unchanged_paths = [
    "apps/kernel/backend/memory/tenants/v1.mo",
    "apps/kernel/backend/memory/app_instances/v1.mo",
    "apps/kernel/backend/memory/app_instance_lifecycle/v1.mo",
    "apps/kernel/backend/memory/app_catalog/v1.mo",
    "apps/kernel/backend/app_instances/Allocation.mo",
]
for relative in unchanged_paths:
    current = (ROOT / relative).read_text()
    require(
        current == git_show(relative),
        f"0.1 persistence/allocator source changed: {relative}",
    )

print("Upgrade schema gate passed: existing 0.1 roots/locks unchanged")
print("Upgrade schema gate passed: three authorization v1 roots added without migrations")
print("Upgrade schema gate passed: 0.1 allocator and persistence source unchanged")
