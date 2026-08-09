import { execFile, spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { disposeMotokoCompiler, loadMotoko } from "neutron-motoko-wasm";
import {
  parsePackageString,
  type PackageMap,
} from "neutron-scripts/src/walk.js";
import {
  createMotokoProgramPreparationCache,
  prepareMotokoProgram,
} from "neutron-scripts/src/motoko.js";

const execute = promisify(execFile);
const compiledTests = [
  "authenticated_forest_test.mo",
  "capability_registry_test.mo",
  "certified_assets_allocator_test.mo",
  "certified_assets_service_test.mo",
  "connections_codec_test.mo",
  "connections_memory_test.mo",
  "painless_test.mo",
];
const interpretedTests = [
  "authenticated_forest_lifecycle_test.mo",
  "backend_calls_test.mo",
  "chain_key_signing_service_test.mo",
  "certified_assets_codec_test.mo",
  "certified_assets_incremental_sha256_test.mo",
  "certified_assets_public_surface_test.mo",
  "connections_service_test.mo",
  "frontend_runtime_admission_test.mo",
  "gateway_authority_test.mo",
  "http_privacy_test.mo",
  "http_certification_test.mo",
  "memory_v3_schema_test.mo",
  "http_post_update_handlers_service_test.mo",
  "https_outcalls_service_test.mo",
  "app_usage_service_test.mo",
  "activation_service_test.mo",
  "app_instance_allocation_test.mo",
  "public_ingress_service_test.mo",
  "install_service_test.mo",
  "randomness_service_test.mo",
  "scheduler_memory_test.mo",
  "stable_store_service_test.mo",
  "vetkeys_memory_test.mo",
  "vetkeys_service_test.mo",
];
const allTests = [...compiledTests, ...interpretedTests];
const requestedTests = process.env.MOTOKO_TEST?.split(",")
  .map((test) => test.trim())
  .filter(Boolean);
const tests = requestedTests
  ? allTests.filter((test) => requestedTests.includes(test))
  : allTests;
if (tests.length === 0) {
  throw new Error(`Unknown MOTOKO_TEST: ${process.env.MOTOKO_TEST}`);
}
if (requestedTests && tests.length !== new Set(requestedTests).size) {
  const unknown = requestedTests.filter((test) => !allTests.includes(test));
  throw new Error(`Unknown MOTOKO_TEST: ${unknown.join(",")}`);
}
const exactPassTranscript =
  process.env.MOTOKO_EXACT_PASS_TRANSCRIPT === "1";
const workerMode = process.env.MOTOKO_WORKER === "1";
const motokoJobs = resolveMotokoJobs(tests.length);
const parallelMode =
  !workerMode &&
  !exactPassTranscript &&
  motokoJobs > 1 &&
  tests.length > 1;

if (parallelMode) {
  console.log(
    `Running ${tests.length} Motoko tests with ${motokoJobs} workers`,
  );
  await runParallelWorkers(tests, motokoJobs);
} else {
const cwd = process.cwd();
const testRoot = path.resolve("test/motoko");
const temporary = await fs.mkdtemp(
  path.join(os.tmpdir(), "neutron-motoko-test-"),
);

const originalConsoleLog = console.log;
if (exactPassTranscript) {
  console.log = () => {};
}

try {
  const packages = await resolvePackages(cwd);
  const mo = await loadMotoko();
  const preparationCache = createMotokoProgramPreparationCache();
  let wasmtime: string | undefined;

  for (const [index, test] of tests.entries()) {
    if (!exactPassTranscript) {
      console.log(`[${index + 1}/${tests.length}] Motoko test: ${test}`);
    }
    const prepared = await prepareMotokoProgram({
      compiler: mo,
      sourcePath: path.join(testRoot, test),
      packages,
      allowDangerous: true,
      cache: preparationCache,
    });

    if (interpretedTests.includes(test)) {
      await mo.run(prepared.entryPath);
      reportPass(test);
      continue;
    }

    const compiled = await mo.wasm(prepared.entryPath, "wasi");
    const wasmPath = path.join(temporary, `${index}.wasm`);
    await fs.writeFile(wasmPath, compiled.wasm);
    wasmtime ??= await resolveWasmtime();
    await execute(wasmtime, ["-W", "memory64=y", wasmPath]);
    reportPass(test);
  }
} finally {
  console.log = originalConsoleLog;
  await disposeMotokoCompiler();
  await fs.rm(temporary, { recursive: true, force: true });
}

}

function resolveMotokoJobs(testCount: number): number {
  const configured = process.env.MOTOKO_JOBS;
  if (configured !== undefined) {
    if (!/^[1-9]\d*$/u.test(configured)) {
      throw new Error("MOTOKO_JOBS must be a positive integer");
    }
    return Math.min(Number(configured), testCount);
  }

  const available =
    typeof os.availableParallelism === "function"
      ? os.availableParallelism()
      : os.cpus().length;

  return Math.max(1, Math.min(4, available, testCount));
}

async function runParallelWorkers(
  selectedTests: string[],
  jobs: number,
): Promise<void> {
  const groups = Array.from({ length: jobs }, () => [] as string[]);

  for (const [index, test] of selectedTests.entries()) {
    groups[index % jobs]!.push(test);
  }

  const runnerPath = path.resolve(process.argv[1]!);

  await Promise.all(
    groups
      .filter((group) => group.length > 0)
      .map(
        (group, workerIndex) =>
          new Promise<void>((resolve, reject) => {
            const child = spawn(process.execPath, [runnerPath], {
              cwd: process.cwd(),
              stdio: ["ignore", "inherit", "inherit"],
              env: {
                ...process.env,
                MOTOKO_WORKER: "1",
                MOTOKO_TEST: group.join(","),
                MOTOKO_EXACT_PASS_TRANSCRIPT: "1",
              },
            });

            child.once("error", reject);
            child.once("exit", (code, signal) => {
              if (code === 0) {
                resolve();
                return;
              }

              reject(
                new Error(
                  `Motoko worker ${workerIndex + 1} failed ` +
                    `(exit=${code ?? "null"}, signal=${signal ?? "none"})`,
                ),
              );
            });
          }),
      ),
  );
}

async function resolvePackages(cwd: string): Promise<PackageMap> {
  const boundPackages = process.env.MOTOKO_PACKAGES_JSON;
  if (boundPackages === undefined) {
    const sourceOutput = await execute("mops", ["sources"], { cwd });
    return parsePackageString(
      sourceOutput.stdout.replace(/\n/g, " ").trim(),
    );
  }
  let decoded: unknown;
  try {
    decoded = JSON.parse(boundPackages);
  } catch {
    throw new Error("MOTOKO_PACKAGES_JSON must be valid JSON");
  }
  if (
    decoded === null ||
    typeof decoded !== "object" ||
    Array.isArray(decoded)
  ) {
    throw new Error("MOTOKO_PACKAGES_JSON must be a package map");
  }
  const packages: PackageMap = {};
  for (const [name, sourceRoot] of Object.entries(decoded)) {
    if (
      !/^[A-Za-z0-9_.@-]+$/u.test(name) ||
      typeof sourceRoot !== "string" ||
      !path.isAbsolute(sourceRoot) ||
      path.resolve(sourceRoot) !== sourceRoot
    ) {
      throw new Error("MOTOKO_PACKAGES_JSON contains an invalid package root");
    }
    const metadata = await fs.lstat(sourceRoot);
    if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
      throw new Error(
        "MOTOKO_PACKAGES_JSON package roots must be real directories",
      );
    }
    packages[name] = sourceRoot;
  }
  if (Object.keys(packages).length === 0) {
    throw new Error("MOTOKO_PACKAGES_JSON must not be empty");
  }
  return packages;
}

function reportPass(test: string): void {
  const line = `Motoko test passed: ${test}`;
  if (exactPassTranscript) {
    process.stdout.write(`${line}\n`);
  } else {
    console.log(line);
  }
}

async function resolveWasmtime(): Promise<string> {
  const configured = process.env.WASMTIME;
  if (configured) {
    await fs.access(configured, fs.constants.X_OK);
    return configured;
  }

  for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
    if (!directory) continue;
    const candidate = path.join(directory, "wasmtime");
    try {
      await fs.access(candidate, fs.constants.X_OK);
      return candidate;
    } catch {}
  }

  try {
    const entries = (await fs.readdir("/nix/store"))
      .filter((entry) => entry.includes("-wasmtime-"))
      .sort()
      .reverse();
    for (const entry of entries) {
      const candidate = path.join("/nix/store", entry, "bin", "wasmtime");
      try {
        await fs.access(candidate, fs.constants.X_OK);
        return candidate;
      } catch {}
    }
  } catch {}

  throw new Error("wasmtime is required to execute Motoko unit tests");
}
