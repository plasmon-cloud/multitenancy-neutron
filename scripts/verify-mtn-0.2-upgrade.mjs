#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "origin/version-0.1.0";
const MANIFEST = "apps/kernel/neutron.json";
const LOCK = "apps/kernel/neutron.lock.json";

function gitShow(path) {
  return execFileSync("git", ["show", `${BASE}:${path}`], {
    cwd: ROOT,
    encoding: "utf8",
  });
}

function read(path) {
  return readFileSync(resolve(ROOT, path), "utf8");
}

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

const oldManifest = JSON.parse(gitShow(MANIFEST));
const newManifest = JSON.parse(read(MANIFEST));
const oldLock = JSON.parse(gitShow(LOCK));
const newLock = JSON.parse(read(LOCK));

for (const [root, definition] of Object.entries(oldManifest.memory)) {
  requireCondition(root in newManifest.memory, `missing existing memory root: ${root}`);
  requireCondition(
    JSON.stringify(newManifest.memory[root]) === JSON.stringify(definition),
    `existing memory manifest changed: ${root}`,
  );
}

const authorizationInitArgs = [
  "memory_authorization_grants",
  "memory_authorization_resource_epochs",
  "memory_authorization_audit",
];
const firstNonMemory = oldManifest.init_arg.findIndex(
  (value) => !value.startsWith("memory_"),
);
requireCondition(firstNonMemory >= 0, "0.1 initializer has no non-memory arguments");
const expectedInit = [
  ...oldManifest.init_arg.slice(0, firstNonMemory),
  ...authorizationInitArgs,
  ...oldManifest.init_arg.slice(firstNonMemory),
];
requireCondition(
  JSON.stringify(newManifest.init_arg) === JSON.stringify(expectedInit),
  "0.1 initializer argument order/identity changed",
);

const expectedNewRoots = new Map([
  ["authorization_grants", "memory/authorization_grants/v1.mo"],
  ["authorization_resource_epochs", "memory/authorization_resource_epochs/v1.mo"],
  ["authorization_audit", "memory/authorization_audit/v1.mo"],
]);
const oldRoots = new Set(Object.keys(oldManifest.memory));
const actualNewRoots = Object.keys(newManifest.memory)
  .filter((root) => !oldRoots.has(root))
  .sort();
requireCondition(
  JSON.stringify(actualNewRoots) === JSON.stringify([...expectedNewRoots.keys()].sort()),
  `unexpected 0.2 memory roots: ${actualNewRoots.join(",")}`,
);

for (const [root, source] of expectedNewRoots) {
  const definition = newManifest.memory[root];
  requireCondition(definition?.version === 1, `${root}: expected version 1`);
  requireCondition(
    JSON.stringify(definition?.migrations) === "[]",
    `${root}: unexpected migration`,
  );
  requireCondition(
    definition?.schemas?.["1"]?.src === source,
    `${root}: unexpected schema source`,
  );
}

for (const [root, definition] of Object.entries(oldLock.memory)) {
  requireCondition(root in newLock.memory, `lock lost existing root: ${root}`);
  requireCondition(
    JSON.stringify(newLock.memory[root]) === JSON.stringify(definition),
    `existing lock/schema identity changed: ${root}`,
  );
}

const oldLockRoots = new Set(Object.keys(oldLock.memory));
const actualNewLockRoots = Object.keys(newLock.memory)
  .filter((root) => !oldLockRoots.has(root))
  .sort();
requireCondition(
  JSON.stringify(actualNewLockRoots) === JSON.stringify([...expectedNewRoots.keys()].sort()),
  `unexpected 0.2 lock roots: ${actualNewLockRoots.join(",")}`,
);

for (const root of expectedNewRoots.keys()) {
  const definition = newLock.memory[root];
  requireCondition(definition?.schemas?.["1"], `lock missing ${root} v1 schema`);
  requireCondition(
    JSON.stringify(definition?.migrations ?? {}) === "{}",
    `lock contains unexpected ${root} migration`,
  );
}

const unchangedPaths = [
  "apps/kernel/backend/memory/tenants/v1.mo",
  "apps/kernel/backend/memory/app_instances/v1.mo",
  "apps/kernel/backend/memory/app_instance_lifecycle/v1.mo",
  "apps/kernel/backend/memory/app_catalog/v1.mo",
  "apps/kernel/backend/app_instances/Allocation.mo",
];
for (const path of unchangedPaths) {
  requireCondition(
    read(path) === gitShow(path),
    `0.1 persistence/allocator source changed: ${path}`,
  );
}

console.log("Upgrade schema gate passed: existing 0.1 roots/locks unchanged");
console.log("Upgrade schema gate passed: three authorization v1 roots added without migrations");
console.log("Upgrade schema gate passed: 0.1 allocator and persistence source unchanged");
