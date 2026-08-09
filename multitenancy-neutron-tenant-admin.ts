import { Actor, HttpAgent } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";
import { localIdentityFromSeed } from "./packages/neutron-provision/src/kernel.ts";

const [action, canisterId, arg1, arg2] = Bun.argv.slice(2);

if (
  ![
    "grant",
    "revoke",
    "list",
    "register",
    "instances",
  ].includes(action ?? "") ||
  !canisterId
) {
  console.error(
    "Usage:\n" +
      "  bun multitenancy-neutron-tenant-admin.ts grant     CANISTER PRINCIPAL APP_INSTANCE_ID\n" +
      "  bun multitenancy-neutron-tenant-admin.ts revoke    CANISTER PRINCIPAL APP_INSTANCE_ID\n" +
      "  bun multitenancy-neutron-tenant-admin.ts list      CANISTER PRINCIPAL\n" +
      "  bun multitenancy-neutron-tenant-admin.ts register  CANISTER APP_ID APP_INSTANCE_ID\n" +
      "  bun multitenancy-neutron-tenant-admin.ts instances CANISTER APP_ID",
  );
  process.exit(1);
}

const idlFactory = ({ IDL }: { IDL: typeof import("@dfinity/candid").IDL }) =>
  IDL.Service({
    kernel_tenant_grant: IDL.Func(
      [IDL.Record({ principal: IDL.Principal, app_id: IDL.Text })],
      [],
      [],
    ),
    kernel_tenant_revoke: IDL.Func(
      [IDL.Record({ principal: IDL.Principal, app_id: IDL.Text })],
      [],
      [],
    ),
    kernel_tenant_apps: IDL.Func(
      [IDL.Record({ principal: IDL.Principal })],
      [IDL.Vec(IDL.Text)],
      ["query"],
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
  });

type TenantActor = {
  kernel_tenant_grant(input: { principal: Principal; app_id: string }): Promise<void>;
  kernel_tenant_revoke(input: { principal: Principal; app_id: string }): Promise<void>;
  kernel_tenant_apps(input: { principal: Principal }): Promise<string[]>;
  kernel_app_instance_register(input: { app_id: string; app_instance_id: string }): Promise<void>;
  kernel_app_instances_for_app(input: { app_id: string }): Promise<string[]>;
};

const identity = localIdentityFromSeed(2);
console.log("Admin principal:", identity.getPrincipal().toText());

const agent = await HttpAgent.create({
  host: "http://127.0.0.1:8000",
  identity,
  verifyQuerySignatures: false,
});
await agent.fetchRootKey();

const actor = Actor.createActor<TenantActor>(idlFactory, {
  agent,
  canisterId: Principal.fromText(canisterId),
});

switch (action) {
  case "grant": {
    if (!arg1 || !arg2) throw new Error("grant requires PRINCIPAL APP_INSTANCE_ID");
    const principal = Principal.fromText(arg1);
    await actor.kernel_tenant_grant({ principal, app_id: arg2 });
    console.log(`Granted ${arg1} -> ${arg2}`);
    console.log("Tenant apps:", await actor.kernel_tenant_apps({ principal }));
    break;
  }
  case "revoke": {
    if (!arg1 || !arg2) throw new Error("revoke requires PRINCIPAL APP_INSTANCE_ID");
    const principal = Principal.fromText(arg1);
    await actor.kernel_tenant_revoke({ principal, app_id: arg2 });
    console.log(`Revoked ${arg1} -> ${arg2}`);
    console.log("Tenant apps:", await actor.kernel_tenant_apps({ principal }));
    break;
  }
  case "list": {
    if (!arg1) throw new Error("list requires PRINCIPAL");
    const principal = Principal.fromText(arg1);
    console.log("Tenant apps:", await actor.kernel_tenant_apps({ principal }));
    break;
  }
  case "register": {
    if (!arg1 || !arg2) throw new Error("register requires APP_ID APP_INSTANCE_ID");
    await actor.kernel_app_instance_register({ app_id: arg1, app_instance_id: arg2 });
    console.log(`Registered ${arg2} -> ${arg1}`);
    console.log("App instances:", await actor.kernel_app_instances_for_app({ app_id: arg1 }));
    break;
  }
  case "instances": {
    if (!arg1) throw new Error("instances requires APP_ID");
    console.log("App instances:", await actor.kernel_app_instances_for_app({ app_id: arg1 }));
    break;
  }
}
