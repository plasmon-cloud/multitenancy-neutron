import { main } from "./packages/neutron-provision/src/cli.ts";
import {
  runLocalReinstall,
  type LocalReinstallResult,
} from "./packages/neutron-provision/src/local_deploy.ts";
import { bootstrapAppPools } from "./multitenancy-neutron-bootstrap.ts";

const [configPath, command] = Bun.argv.slice(2);

if (!configPath || command !== "reinstall") {
  console.error(
    "Usage: bun multitenancy-neutron-provision.ts CONFIG.ndeploy.json reinstall",
  );
  process.exit(1);
}

let deploymentResult: LocalReinstallResult | undefined;

await main(
  [configPath, "reinstall"],
  console,
  {
    localReinstall: async (options, dependencies) => {
      const result = await runLocalReinstall(options, dependencies);
      deploymentResult = result;
      return result;
    },
  },
);

if (!deploymentResult) {
  throw new Error(
    "multitenancy-neutron bootstrap currently supports PocketIC reinstall only",
  );
}

const runtime = deploymentResult.session.runtime;
if (runtime.kind !== "pocketic") {
  throw new Error(
    "multitenancy-neutron local bootstrap expected a PocketIC runtime",
  );
}

console.log("");
console.log("Seeding multitenancy-neutron app catalog and pools...");

for (const node of deploymentResult.nodes) {
  console.log("");
  console.log(`Node ${node.label}: ${node.canisterId}`);
  await bootstrapAppPools({
    canisterId: node.canisterId,
    host: runtime.gateway.url,
  });
}

console.log("");
console.log("multitenancy-neutron deployment ready.");
for (const node of deploymentResult.nodes) {
  console.log(`${node.label}: ${node.canisterId} ${node.url}`);
}
