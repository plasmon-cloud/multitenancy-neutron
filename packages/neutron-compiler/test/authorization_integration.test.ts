import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { appPhysicalStem } from "neutron-tools/src/physical_names.js";
import { assemble, type AssemblyManifest } from "../src/assemble.ts";
import { compile } from "../src/compile.ts";

const moduleHash = (digit: string): string => digit.repeat(64);

const realKernelSource = await readFile(
  new URL("../../../apps/kernel/backend/main.mo", import.meta.url),
  "utf8",
);
const publicCapabilitiesSource = await readFile(
  new URL("../../neutron-motoko-capabilities/src/lib.mo", import.meta.url),
  "utf8",
);

test("authorization interface closes the manifest-to-real-Kernel-to-app typecheck chain", async () => {
  // This is intentionally tied to the production Kernel source, not merely a
  // compiler fixture. Removing or changing the real exact-scope factory makes
  // this integration test fail before the synthetic compile is attempted.
  expect(realKernelSource).toMatch(
    /public func authorization_capability\(\s*appScope\s*:\s*CapabilityTypes\.AppScope,?\s*\)\s*:\s*AuthorizationTypes\.AuthorizationCapabilityV1\s*\{\s*authorization\.authorizationCapability\(appScope\);\s*\}/s,
  );
  expect(realKernelSource).not.toMatch(
    /kernel_authorization_(?:issue|list|revoke|rotate_resource|release)\b/,
  );
  expect(publicCapabilitiesSource).toContain("public type AuthorizationV1");

  const assemblyKernel: AssemblyManifest = {
    format: 3,
    id: "kernel",
    name: "Kernel",
    version: 100,
    src: "main.mo",
    entry: "kernel",
    func: {
      is_authorized: { type: "internal", async: false },
    },
  };
  const assemblyProvider: AssemblyManifest = {
    format: 3,
    id: "provider_app",
    name: "Provider App",
    version: 100,
    src: "main.mo",
    entry: "provider_app",
    backend: {
      capabilities: {
        authorization: { api: 1 },
      },
    },
  };
  const assembled = assemble({
    kernel: assemblyKernel,
    provider_app: assemblyProvider,
  });
  const stem = appPhysicalStem("provider_app");
  const scopeName = `NeutronAppScope_${stem}`;
  const environmentName = `NeutronAppEnvironment_${stem}`;
  expect(assembled).toContain(
    `transient let ${scopeName} = NeutronKernel.app_scope("provider_app", "development")`,
  );
  expect(assembled).toMatch(
    new RegExp(
      `${environmentName} = \\{[\\s\\S]*?capabilities = \\{[\\s\\S]*?authorization = NeutronKernel\\.authorization_capability\\(${scopeName}\\);`,
    ),
  );
  expect(assembled).not.toContain("authorization_capability(NeutronCaller");

  const kernelEntry = moduleHash("a");
  const providerEntry = moduleHash("b");
  const capabilitiesEntry = moduleHash("c");

  const result = await compile({
    configs: {
      kernel: {
        format: 3,
        id: "kernel",
        name: "Kernel",
        version: 100,
        entry: kernelEntry,
      },
      provider_app: {
        format: 3,
        id: "provider_app",
        name: "Provider App",
        version: 100,
        entry: providerEntry,
        backend: {
          capabilities: {
            authorization: { api: 1 },
          },
        },
      },
    },
    mofiles: [
      {
        path: `${kernelEntry}.mo`,
        content: `module {
          public type AppScope = { app_id : Text; installation_uid : Nat64 };
          public type AppInstance = {
            scope : AppScope;
            version : Nat;
            deployment_id : Text;
            capability_plan_fingerprint : Text;
            resident_frame_security : {
              #credentialless_opaque_v1;
              #credentialless_ephemeral_dedicated_v1;
              #persistent_dedicated_v1;
            };
            browser_origin_nonce : Text;
            browser_origin_authority_epoch : Nat64;
          };
          public class Init() {
            public func app_scope(appId : Text, _deploymentId : Text) : AppScope {
              { app_id = appId; installation_uid = 7 }
            };
            public func runtime_app_instances(_deploymentId : Text) : [AppInstance] { [] };
            public func scope_active(_scope : AppScope) : Bool { true };
            public func is_session_authorized(_caller : Principal) : Bool { true };
            public func is_app_authorized(
              _input : { caller : Principal; scope : AppScope },
            ) : Bool { true };
            public func configure_app_capabilities<T, U>(
              _declarations : [T],
              _configuration : U,
            ) {};
            public func configure_frontend_surface_counts<T>(_counts : T) {};
            public func configure_capability_registry<T>(
              _registrations : [T],
              _self : actor {},
            ) {};
            public func authorization_capability<T>(_scope : AppScope) : T {
              loop {};
            };
            public func kernel_authorized_add(_caller : Principal) {};
            public func is_authorized(_caller : Principal) : Bool { true };
          };
        }`,
      },
      {
        path: `${providerEntry}.mo`,
        content: `import Capabilities "${capabilitiesEntry}";
        module {
          public type Environment = {
            capabilities : {
              authorization : Capabilities.AuthorizationV1;
            };
          };
          public class Init(environment : Environment) {
            public func grantCount() : Nat {
              environment.capabilities.authorization.list().size();
            };
            public func issueProbe() : async* Bool {
              switch (await* environment.capabilities.authorization.issue({
                resource = {
                  namespace = "provider.test";
                  resource_id = "resource-1";
                  resource_type = "document/v1";
                };
                audience = #any_authenticated;
                consumer_element = null;
                rights = [#read];
                expires_at = null;
                max_redemptions = ?1;
              })) {
                case (#ok(output)) output.token.size() > 0;
                case (#err(_)) false;
              };
            };
          };
        }`,
      },
      {
        path: `${capabilitiesEntry}.mo`,
        content: publicCapabilitiesSource,
      },
    ],
  });

  expect(result.wasm.byteLength).toBeGreaterThan(0);
  expect(result.capabilityPlans.provider_app?.plan.entries).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        id: "backend_environment",
        config: { interfaces: [{ id: "authorization", api: 1 }] },
      }),
    ]),
  );
});
