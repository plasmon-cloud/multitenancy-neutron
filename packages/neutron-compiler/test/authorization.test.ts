import { expect, test } from "bun:test";
import { appPhysicalStem } from "neutron-tools/src/physical_names.js";
import { assemble, type AssemblyManifest } from "../src/assemble.ts";

const kernel: AssemblyManifest = {
  format: 3,
  id: "kernel",
  name: "Kernel",
  version: 100,
  src: "main.mo",
  entry: "kernel",
  init_arg: ["memory_kernel"],
  func: {
    is_authorized: { type: "internal", async: false },
    kernel_install_code: { type: "update", async: true, arg: ["this"] },
    kernel_install_commit: {
      type: "update",
      async: false,
      arg: ["caller"],
    },
    kernel_install_reservations_prepare: {
      type: "update",
      async: false,
      arg: ["caller"],
    },
    kernel_connections_begin: {
      type: "update",
      async: "async*",
      arg: ["caller", "this"],
    },
    kernel_https_outcall_transform: {
      type: "query",
      async: false,
      arg: ["caller"],
      allow: "unauthorized",
    },
  },
  memory: {
    kernel: {
      version: 1,
      schemas: { "1": { src: "memory/kernel.mo" } },
      migrations: [],
    },
  },
};

const provider: AssemblyManifest = {
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

test("authorization backend capability is compiler-bound to exact AppScope", () => {
  const source = assemble({ kernel, provider_app: provider });
  const stem = appPhysicalStem("provider_app");
  const scope = `NeutronAppScope_${stem}`;
  const environment = `NeutronAppEnvironment_${stem}`;

  expect(source).toContain(
    `transient let ${scope} = NeutronKernel.app_scope("provider_app", "development")`,
  );
  expect(source).toMatch(
    new RegExp(
      `${environment} = \\{[\\s\\S]*?capabilities = \\{[\\s\\S]*?authorization = NeutronKernel\\.authorization_capability\\(${scope}\\);`,
    ),
  );
  expect(source).not.toContain("authorization_capability(NeutronCaller");
});
