import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { preparePackageInstall } from "neutron-compiler/src/install.js";

/**
 * Validate outputs produced by `npm run package`.
 *
 * This file intentionally does not use Bun's normal `*.test.ts` naming so
 * ordinary source tests never consume potentially stale dist/package output.
 * The kernel package script invokes it only after producing fresh artifacts.
 */
test("kernel package contains the expected manifest, lock and candid", async () => {
  const [
    manifestText,
    lockText,
    packagedManifestText,
    packagedLockText,
    candid,
    archive,
  ] = await Promise.all([
    readFile(new URL("../neutron.json", import.meta.url), "utf8"),
    readFile(new URL("../neutron.lock.json", import.meta.url), "utf8"),
    readFile(new URL("../dist/neutron.json", import.meta.url), "utf8"),
    readFile(new URL("../dist/neutron.lock.json", import.meta.url), "utf8"),
    readFile(new URL("../dist/neutron.did", import.meta.url), "utf8"),
    readFile(new URL("../kernel.v0.3.6.neutron", import.meta.url)),
  ]);

  const manifest = JSON.parse(manifestText);
  const lock = JSON.parse(lockText);
  const packagedManifest = JSON.parse(packagedManifestText);
  const packagedLock = JSON.parse(packagedLockText);
  const packagedArchive = preparePackageInstall(new Uint8Array(archive));

  expect(packagedManifest.format).toBe(manifest.format);
  expect(packagedManifest.version).toBe(manifest.version);
  expect(packagedManifest.update_source).toBe(manifest.update_source);

  expect(packagedManifest.memory.kernel.version).toBe(3);
  expect(Object.keys(packagedManifest.memory.kernel.schemas)).toEqual(["3"]);
  expect(packagedManifest.memory.kernel.migrations).toBeUndefined();

  expect(packagedManifest.memory.kernel_activation.version).toBe(1);
  expect(packagedManifest.memory.kernel_activation.migrations).toEqual([]);

  for (const root of [
    "authorization_grants",
    "authorization_resource_epochs",
    "authorization_audit",
  ]) {
    expect(packagedManifest.memory[root].version).toBe(1);
    expect(Object.keys(packagedManifest.memory[root].schemas)).toEqual(["1"]);
    expect(packagedManifest.memory[root].migrations).toEqual([]);
    expect(packagedLock.memory[root].schemas["1"]).toBeDefined();
    expect(Object.keys(packagedLock.memory[root].migrations ?? {})).toHaveLength(0);

    expect(packagedArchive.manifest.memory?.[root]?.version).toBe(1);
    expect(
      Object.keys(packagedArchive.manifest.memory?.[root]?.schemas ?? {}),
    ).toEqual(["1"]);
    expect(packagedArchive.manifest.memory?.[root]?.migrations).toEqual([]);
  }

  expect(packagedLock).toEqual(lock);

  expect(packagedArchive.manifest.memory?.kernel?.version).toBe(3);
  expect(
    Object.keys(packagedArchive.manifest.memory?.kernel?.schemas ?? {}),
  ).toEqual(["3"]);
  expect(
    packagedArchive.manifest.memory?.kernel?.migrations,
  ).toBeUndefined();
  expect(
    packagedArchive.manifest.memory?.kernel_activation?.version,
  ).toBe(1);

  expect(candid).toContain("kernel_activation:");

  for (const method of [
    "kernel_authorization_capabilities",
    "kernel_authorization_inspect",
    "kernel_authorization_redeem",
    "kernel_certified_assets_scope_info",
    "kernel_certified_assets_usage",
    "kernel_certified_assets_diagnostics",
    "kernel_certified_assets_set_admission_ceilings",
    "kernel_certified_assets_set_writes_frozen",
    "kernel_certified_assets_maintenance_page",
    "kernel_certified_assets_retire_scope",
    "kernel_publication_entropy_initialize",
  ]) {
    expect(candid).toContain(`${method}:`);
  }

  for (const forbidden of [
    "kernel_authorization_issue",
    "kernel_authorization_list",
    "kernel_authorization_revoke",
    "kernel_authorization_rotate_resource",
    "kernel_authorization_release",
  ]) {
    expect(candid).not.toContain(`${forbidden}:`);
  }
});
