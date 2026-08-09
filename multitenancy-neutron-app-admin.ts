import { Actor, HttpAgent } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";
import { localIdentityFromSeed } from "./packages/neutron-provision/src/kernel.ts";

const [action, canisterId, appId, name, description = ""] =
  Bun.argv.slice(2);

if (
  !["register", "get"].includes(action ?? "") ||
  !canisterId ||
  !appId
) {
  console.error(
    "Usage:\n" +
      "  bun multitenancy-neutron-app-admin.ts register CANISTER APP_ID NAME DESCRIPTION\n" +
      "  bun multitenancy-neutron-app-admin.ts get      CANISTER APP_ID",
  );
  process.exit(1);
}

const idlFactory = ({ IDL }: { IDL: typeof import("@dfinity/candid").IDL }) =>
  IDL.Service({
    kernel_app_catalog_register: IDL.Func(
      [
        IDL.Record({
          app_id: IDL.Text,
          name: IDL.Text,
          description: IDL.Text,
        }),
      ],
      [],
      [],
    ),

    kernel_app_catalog_get: IDL.Func(
      [
        IDL.Record({
          app_id: IDL.Text,
        }),
      ],
      [IDL.Vec(IDL.Text)],
      ["query"],
    ),
  });

type CatalogActor = {
  kernel_app_catalog_register(input: {
    app_id: string;
    name: string;
    description: string;
  }): Promise<void>;

  kernel_app_catalog_get(input: {
    app_id: string;
  }): Promise<string[]>;
};

const identity = localIdentityFromSeed(2);

const agent = await HttpAgent.create({
  host: "http://127.0.0.1:8000",
  identity,
  verifyQuerySignatures: false,
});

await agent.fetchRootKey();

const actor = Actor.createActor<CatalogActor>(idlFactory, {
  agent,
  canisterId: Principal.fromText(canisterId),
});

switch (action) {
  case "register":
    if (!name) throw new Error("register requires NAME");

    await actor.kernel_app_catalog_register({
      app_id: appId,
      name,
      description,
    });

    console.log(`Registered app ${appId}`);
    console.log(
      await actor.kernel_app_catalog_get({
        app_id: appId,
      }),
    );
    break;

  case "get":
    console.log(
      await actor.kernel_app_catalog_get({
        app_id: appId,
      }),
    );
    break;
}
