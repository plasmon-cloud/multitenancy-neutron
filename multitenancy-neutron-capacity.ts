import fs from "node:fs/promises";
import path from "node:path";
import { packDirectory } from "./packages/neutron-scripts/src/pack.ts";

type PoolApp = {
  app_id: string;
  template: string;
  name: string;
  description: string;
  capacity: number;
};

type PoolConfig = { apps: PoolApp[] };
type JsonObject = Record<string, any>;

const poolConfigPath =
  Bun.argv[2] ?? "multitenancy-neutron-app-pools.json";
const deployTemplatePath =
  Bun.argv[3] ?? "multitenancy-neutron-base.ndeploy.json";
const outputDeployPath =
  Bun.argv[4] ?? "multitenancy-neutron.ndeploy.json";

const cwd = process.cwd();
const generatedRoot = path.resolve(cwd, ".multitenancy-neutron-generated");

async function readJson<T>(file: string): Promise<T> {
  return JSON.parse(await fs.readFile(file, "utf8")) as T;
}

async function writeJson(file: string, value: unknown): Promise<void> {
  await fs.writeFile(file, JSON.stringify(value, null, 2) + "\n");
}

function instanceId(appId: string, index: number): string {
  return `${appId}_${String(index + 1).padStart(3, "0")}`;
}

function rewriteManifest(
  source: JsonObject,
  app: PoolApp,
  id: string,
): JsonObject {
  const manifest = structuredClone(source);
  manifest.id = id;
  manifest.name = app.name;

  if (Array.isArray(manifest.tiles)) {
    manifest.tiles = manifest.tiles.map((tile: JsonObject) => ({
      ...tile,
      title: app.name,
    }));
  }
  return manifest;
}

function validate(config: PoolConfig): void {
  if (!Array.isArray(config.apps) || config.apps.length === 0) {
    throw new Error("config.apps must contain at least one app");
  }

  const logicalIds = new Set<string>();
  for (const app of config.apps) {
    if (!app.app_id) throw new Error("app_id cannot be empty");
    if (logicalIds.has(app.app_id)) {
      throw new Error(`duplicate logical app_id: ${app.app_id}`);
    }
    logicalIds.add(app.app_id);
    if (!app.template) {
      throw new Error(`${app.app_id}: template cannot be empty`);
    }
    if (!Number.isInteger(app.capacity) || app.capacity < 1) {
      throw new Error(`${app.app_id}: capacity must be a positive integer`);
    }
  }
}

const config = await readJson<PoolConfig>(poolConfigPath);
validate(config);

await fs.rm(generatedRoot, { recursive: true, force: true });
await fs.mkdir(generatedRoot, { recursive: true });

const packages: Array<{ path: string }> = [];

for (const app of config.apps) {
  const templateRoot = path.resolve(cwd, app.template);
  const templateDist = path.join(templateRoot, "dist");
  const rootManifest = await readJson<JsonObject>(
    path.join(templateRoot, "neutron.json"),
  );
  const distManifest = await readJson<JsonObject>(
    path.join(templateDist, "neutron.json"),
  );
  const schema = await readJson<JsonObject>(
    path.join(templateDist, "schema.json"),
  );
  const lock = await readJson<JsonObject>(
    path.join(templateDist, "neutron.lock.json"),
  );

  console.log(
    `Generating ${app.capacity} ${app.app_id} slots from ${app.template}`,
  );

  for (let index = 0; index < app.capacity; index++) {
    const id = instanceId(app.app_id, index);
    const slotRoot = path.join(generatedRoot, "apps", id);
    const slotDist = path.join(slotRoot, "dist");

    await fs.mkdir(slotRoot, { recursive: true });
    await fs.cp(templateDist, slotDist, { recursive: true });

    // packDirectory() reads the root manifest for archive identity.
    await writeJson(
      path.join(slotRoot, "neutron.json"),
      rewriteManifest(rootManifest, app, id),
    );

    // The compiler consumes the packaged dist manifest.
    await writeJson(
      path.join(slotDist, "neutron.json"),
      rewriteManifest(distManifest, app, id),
    );

    const slotSchema = structuredClone(schema);
    if (
      typeof slotSchema.app !== "object" ||
      slotSchema.app === null
    ) {
      throw new Error(`${app.template}: schema.json has no app metadata`);
    }
    slotSchema.app.id = id;
    slotSchema.app.name = app.name;
    await writeJson(path.join(slotDist, "schema.json"), slotSchema);

    const slotLock = structuredClone(lock);
    slotLock.app = id;
    await writeJson(path.join(slotDist, "neutron.lock.json"), slotLock);

    const archivePath = await packDirectory(slotRoot);
    packages.push({
      path: path.relative(cwd, archivePath).split(path.sep).join("/"),
    });
  }
}

const deploy = await readJson<JsonObject>(deployTemplatePath);
const shardConfig = await readJson<{ shared: string[] }>(
  "multitenancy-neutron-shards.json",
);

if (
  !Array.isArray(shardConfig.shared) ||
  shardConfig.shared.length === 0
) {
  throw new Error(
    "multitenancy-neutron-shards.json must define shared nodes",
  );
}

if (typeof deploy.target !== "object" || deploy.target === null) {
  throw new Error(`${deployTemplatePath}: target section missing`);
}
deploy.target.nodes = shardConfig.shared;

if (typeof deploy.artifacts !== "object" || deploy.artifacts === null) {
  throw new Error(`${deployTemplatePath}: artifacts section missing`);
}
deploy.artifacts.packages = packages;

await writeJson(outputDeployPath, deploy);

console.log("");
console.log(`Generated ${packages.length} physical app instances.`);
console.log(`Deployment: ${outputDeployPath}`);
console.log(`Artifacts: ${generatedRoot}`);
