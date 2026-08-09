import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type RefObject,
} from "react";
import {
  IoHardwareChipOutline,
  IoLogOutOutline,
  IoRefresh,
  IoSettingsOutline,
} from "react-icons/io5";
import { getNeutronId } from "../config.ts";
import { logout, useAuthStore } from "../reducer/auth.ts";
import type {
  KernelMemorySnapshot,
  KernelSettingsSnapshot,
} from "../settings/model.ts";
import {
  loadKernelMemorySnapshot,
  loadKernelSettingsSnapshot,
} from "../settings/snapshot.ts";
import { KernelTrayMetrics } from "./KernelTrayMetrics.tsx";
import { TrayPopover } from "./TrayPopover.tsx";

type SnapshotState = {
  data: {
    memory: KernelMemorySnapshot;
    system: KernelSettingsSnapshot;
  } | null;
  error: string | null;
  loading: boolean;
};

export function KernelTrayItem({
  onOpenSettings,
  triggerRef,
}: {
  onOpenSettings: () => void;
  triggerRef: RefObject<HTMLButtonElement | null>;
}) {
  const [snapshot, setSnapshot] = useState<SnapshotState>({
    data: null,
    error: null,
    loading: false,
  });
  const refreshGeneration = useRef(0);
  const canisterId = getNeutronId();

  // MTN session authorization is broader than Neutron owner authorization.
  // Keep metrics and Settings owner-gated: a joined tenant may use its granted
  // AppScopes, but must not inherit kernel administration merely by logging in.
  const owner = useAuthStore((state) => state.owner);

  const refresh = useCallback(async () => {
    if (!owner) return;

    const generation = ++refreshGeneration.current;
    setSnapshot((current) => ({
      ...current,
      error: null,
      loading: true,
    }));

    try {
      const [system, memory] = await Promise.all([
        loadKernelSettingsSnapshot(),
        loadKernelMemorySnapshot(),
      ]);

      if (generation !== refreshGeneration.current) return;

      setSnapshot({
        data: { memory, system },
        error: null,
        loading: false,
      });
    } catch (reason) {
      if (generation !== refreshGeneration.current) return;

      setSnapshot((current) => ({
        ...current,
        error: errorMessage(reason),
        loading: false,
      }));
    }
  }, [owner]);

  useEffect(
    () => () => {
      refreshGeneration.current += 1;
    },
    [],
  );

  useEffect(() => {
    if (owner) return;

    refreshGeneration.current += 1;
    setSnapshot({
      data: null,
      error: null,
      loading: false,
    });
  }, [owner]);

  return (
    <TrayPopover
      buttonLabel="Kernel overview"
      itemClassName="kernel-tray-item"
      onOpenChange={(open) => {
        if (open && owner) void refresh();
      }}
      popoverClassName="app-tray-popover--kernel"
      popoverId="kernel-tray-popover"
      popoverTestId="kernel-tray-popover"
      subtitle="System overview"
      title="Kernel"
      trigger={<IoHardwareChipOutline aria-hidden="true" />}
      triggerRef={triggerRef}
      triggerTestId="kernel-tray-toggle"
    >
      {({ close }) => (
        <div className="kernel-tray-content">
          <section
            className="kernel-tray-overview"
            aria-label="Kernel overview"
          >
            <div className="kernel-tray-section-heading">
              <span>Canister</span>

              {owner ? (
                <button
                  aria-label="Refresh kernel overview"
                  className="icon-button kernel-tray-refresh"
                  data-tid="kernel-tray-retry"
                  disabled={snapshot.loading}
                  onClick={() => void refresh()}
                  title="Refresh kernel overview"
                  type="button"
                >
                  <IoRefresh aria-hidden="true" />
                </button>
              ) : null}
            </div>

            <code>{canisterId}</code>
          </section>

          {owner && snapshot.error ? (
            <div className="kernel-tray-error" role="alert">
              <strong>System metrics are unavailable.</strong>
              <span>{snapshot.error}</span>
            </div>
          ) : null}

          {owner && snapshot.data ? (
            <KernelTrayMetrics
              memory={snapshot.data.memory}
              snapshot={snapshot.data.system}
            />
          ) : owner && snapshot.loading ? (
            <div className="kernel-tray-loading" role="status">
              Loading system metrics…
            </div>
          ) : null}

          <div className="kernel-tray-actions">
            {owner ? (
              <button
                className="kernel-tray-action kernel-tray-action--primary"
                data-tid="kernel-tray-settings"
                onClick={() => {
                  close();
                  onOpenSettings();
                }}
                type="button"
              >
                <IoSettingsOutline aria-hidden="true" />
                <span>Open Settings</span>
              </button>
            ) : null}

            <button
              className="kernel-tray-action"
              data-tid="kernel-tray-logout"
              onClick={() => {
                close();
                void logout();
              }}
              type="button"
            >
              <IoLogOutOutline aria-hidden="true" />
              <span>Logout</span>
            </button>
          </div>
        </div>
      )}
    </TrayPopover>
  );
}

function errorMessage(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason);
}
