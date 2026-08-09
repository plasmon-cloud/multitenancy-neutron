import { Actor, HttpAgent } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";
import { localIdentityFromSeed } from "./packages/neutron-provision/src/kernel.ts";

type AppConfig = {
  app_id: string;
  template?: string;
  name: string;
  description: string;
  capacity?: number;
  instances?: string[];
};

type Config = {
  apps: AppConfig[];
};

type BootstrapOptions = {
  canisterId: string;
  configPath?: string;
  host?: string;
};

const idlFactory = ({
  IDL,
}: {
  IDL: typeof import("@dfinity/candid").IDL;
}) =>
  IDL.Service({
    kernel_app_catalog_register: IDL.Func(
      [IDL.Record({ app_id: IDL.Text, name: IDL.Text, description: IDL.Text })],
      [],
      [],
    ),
    kernel_app_instance_register: IDL.Func(
      [IDL.Record({ app_id: IDL.Text, app_instance_id: IDL.Text })],
      [],
      [],
    ),
    kernel_app_instances_for_app: IDL.Func(
      [IDL.Record({ app_id: IDL.Text })],
      [IDL.Vec(IDL.Text)],
      ["query"],
    ),
    kernel_app_catalog_get: IDL.Func(
      [IDL.Record({ app_id: IDL.Text })],
      [IDL.Vec(IDL.Text)],
      ["query"],
    ),
  });

type BootstrapActor = {
  kernel_app_catalog_register(input: {
    app_id: string;
    name: string;
    description: string;
  }): Promise<void>;
  kernel_app_instance_register(input: {
    app_id: string;
    app_instance_id: string;
  }): Promise<void>;
  kernel_app_instances_for_app(input: { app_id: string }): Promise<string[]>;
  kernel_app_catalog_get(input: { app_id: string }): Promise<string[]>;
};

function appInstanceIds(app: AppConfig): string[] {
  if (Array.isArray(app.instances) && app.instances.length > 0) {
    return app.instances;
  }

  const capacity = app.capacity;
  if (
    typeof capacity !== "number" ||
    !Number.isInteger(capacity) ||
    capacity < 1
  ) {
    throw new Error(`${app.app_id}: capacity must be a positive integer`);
  }

  return Array.from(
    { length: capacity },
    (_, index) => `${app.app_id}_${String(index + 1).padStart(3, "0")}`,
  );
}

function validateConfig(config: Config): void {
  if (!Array.isArray(config.apps)) {
    throw new Error("config.apps must be an array");
  }

  const logicalIds = new Set<string>();
  const physicalIds = new Set<string>();

  for (const app of config.apps) {
    if (!app.app_id) throw new Error("app_id cannot be empty");
    if (!app.name) throw new Error(`${app.app_id}: name cannot be empty`);
    if (logicalIds.has(app.app_id)) {
      throw new Error(`duplicate logical app_id: ${app.app_id}`);
    }
    logicalIds.add(app.app_id);

    for (const instanceId of appInstanceIds(app)) {
      if (physicalIds.has(instanceId)) {
        throw new Error(`physical app instance appears more than once: ${instanceId}`);
      }
      physicalIds.add(instanceId);
    }
  }
}

export async function bootstrapAppPools({
  canisterId,
  configPath = "multitenancy-neutron-app-pools.json",
  host = "http://127.0.0.1:8000",
}: BootstrapOptions): Promise<void> {
  const config = JSON.parse(await Bun.file(configPath).text()) as Config;
  validateConfig(config);

  const identity = localIdentityFromSeed(2);
  const agent = await HttpAgent.create({
    host,
    identity,
    verifyQuerySignatures: false,
  });
  await agent.fetchRootKey();

  const actor = Actor.createActor<BootstrapActor>(idlFactory, {
    agent,
    canisterId: Principal.fromText(canisterId),
  });

  for (const app of config.apps) {
    console.log(`App: ${app.app_id}`);
    await actor.kernel_app_catalog_register({
      app_id: app.app_id,
      name: app.name,
      description: app.description,
    });

    for (const appInstanceId of appInstanceIds(app)) {
      await actor.kernel_app_instance_register({
        app_id: app.app_id,
        app_instance_id: appInstanceId,
      });
    }

    console.log(
      "  metadata:",
      await actor.kernel_app_catalog_get({ app_id: app.app_id }),
    );
    console.log(
      "  instances:",
      await actor.kernel_app_instances_for_app({ app_id: app.app_id }),
    );
  }
}

if (import.meta.main) {
  const [canisterId, configPath] = Bun.argv.slice(2);
  if (!canisterId) {
    console.error(
      "Usage: bun multitenancy-neutron-bootstrap.ts CANISTER [CONFIG]",
    );
    process.exit(1);
  }

  await bootstrapAppPools({
    canisterId,
    ...(configPath ? { configPath } : {}),
  });
  console.log("Bootstrap complete.");
}
