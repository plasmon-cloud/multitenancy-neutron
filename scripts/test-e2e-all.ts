import { spawn } from "node:child_process";
import { once } from "node:events";

type Child = ReturnType<typeof spawn>;

let activeServer: Child | undefined;
let interrupting = false;

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

async function run(
  command: string,
  args: string[],
  extraEnv: Record<string, string> = {},
): Promise<void> {
  const child = spawn(command, args, {
    stdio: "inherit",
    env: { ...process.env, ...extraEnv },
  });

  const [code, signal] = await once(child, "exit");

  if (code !== 0) {
    throw new Error(
      command +
        " " +
        args.join(" ") +
        " failed with " +
        (signal ? "signal " + signal : "exit code " + String(code)),
    );
  }
}

async function startPocketIc(configPath: string): Promise<Child> {
  const child = spawn(
    "bun",
    [
      "packages/neutron-provision/src/index.ts",
      configPath,
      "serve",
    ],
    {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    },
  );

  let output = "";
  let ready = false;

  const readiness = new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(
        new Error(
          "PocketIC did not report readiness for " + configPath,
        ),
      );
    }, 180_000);

    const consume = (
      chunk: Buffer,
      target: NodeJS.WriteStream,
    ) => {
      target.write(chunk);
      output = (output + chunk.toString("utf8")).slice(-16_384);

      if (
        !ready &&
        (
          output.includes("Browser gateway:") ||
          output.includes("to the running PocketIC supervisor")
        )
      ) {
        ready = true;
        clearTimeout(timer);
        resolve();
      }
    };

    child.stdout?.on("data", (chunk: Buffer) =>
      consume(chunk, process.stdout)
    );
    child.stderr?.on("data", (chunk: Buffer) =>
      consume(chunk, process.stderr)
    );

    child.once("exit", (code, signal) => {
      if (ready) return;
      clearTimeout(timer);
      reject(
        new Error(
          "PocketIC serve exited before readiness (" +
            (signal ? "signal " + signal : "code " + String(code)) +
            ")",
        ),
      );
    });
  });

  await readiness;
  return child;
}

async function stopPocketIc(child: Child): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return;

  let exited = once(child, "exit").then(() => true);
  child.kill("SIGINT");

  if (
    await Promise.race([
      exited,
      delay(15_000).then(() => false),
    ])
  ) {
    return;
  }

  exited = once(child, "exit").then(() => true);
  child.kill("SIGTERM");

  if (
    await Promise.race([
      exited,
      delay(5_000).then(() => false),
    ])
  ) {
    return;
  }

  child.kill("SIGKILL");
  await once(child, "exit").catch(() => undefined);
}

async function withPocketIc(
  configPath: string,
  body: () => Promise<void>,
): Promise<void> {
  const server = await startPocketIc(configPath);
  activeServer = server;

  try {
    await body();
  } finally {
    await stopPocketIc(server);
    activeServer = undefined;
  }
}

async function interrupt(exitCode: number): Promise<void> {
  if (interrupting) return;
  interrupting = true;

  if (activeServer) {
    await stopPocketIc(activeServer).catch(() => undefined);
  }

  process.exit(exitCode);
}

process.once("SIGINT", () => void interrupt(130));
process.once("SIGTERM", () => void interrupt(143));

// Ordinary Neutron browser coverage.
await withPocketIc("local.ndeploy.json", async () => {
  await run("npm", ["run", "local:deploy"]);
  await run("npm", ["run", "test:e2e:upstream"]);
});

// Repository-specific multi-tenant browser coverage.
await run("npm", ["run", "multitenancy-neutron:generate"]);

await withPocketIc("multitenancy-neutron.ndeploy.json", async () => {
  await run("bun", [
    "multitenancy-neutron-provision.ts",
    "multitenancy-neutron.ndeploy.json",
    "reinstall",
  ]);
  await run("npm", ["run", "test:e2e:multitenancy"]);
});
