import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react";
import {
  IoAdd,
  IoLinkOutline,
  IoRefresh,
  IoSearch,
  IoTrashOutline,
} from "react-icons/io5";
import {
  appDependencyImpact,
  planAppRegistryDependencies,
} from "neutron-compiler/src/install.js";
import {
  install_app,
  getApps,
  add_app_pool_capacity,
  install_app_pool,
  select_app_pool_package,
  isAuthorityPendingState,
  requestAppUninstall,
  uninstall_app,
  useAppsStore,
  type AppInstallSource,
} from "../reducer/apps.ts";
import {
  allocateAppInstance,
  getAvailableApps,
  getCatalogApps,
  useAuthStore,
} from "../reducer/auth.ts";
import { isAbortError } from "../tools/package_url.ts";
import {
  launcherEntriesFromApps,
  launcherSystemActions,
  type LauncherEntry,
} from "./launcher_entries.ts";
import { useWorkspaceStore } from "./store.ts";
import type { WorkspaceId } from "./types.ts";

type LauncherProps =
  | {
      open: boolean;
      onClose: () => void;
      placement?: "modal";
    }
  | {
      placement: "workspace";
      workspaceId: WorkspaceId;
    };

export function Launcher(props: LauncherProps) {
  const placement = props.placement ?? "modal";
  const open = props.placement === "workspace" ? true : props.open;
  const onClose =
    props.placement === "workspace" ? undefined : props.onClose;
  const idPrefix =
    props.placement === "workspace"
      ? `workspace-launcher-${props.workspaceId}`
      : "launcher";
  const testId = (id: string) =>
    placement === "modal" ? id : `workspace-${id}`;
  const [query, setQuery] = useState("");
  const [availableApps, setAvailableApps] = useState<Awaited<ReturnType<typeof getAvailableApps>>>([]);
  const [allocateBusyAppId, setAllocateBusyAppId] = useState<string | null>(null);
  const [allocateError, setAllocateError] = useState<string | null>(null);
  const [installSource, setInstallSource] = useState<
    "file" | "url" | "pool" | "capacity" | "uninstall" | null
  >(null);
  const [installUrl, setInstallUrl] = useState("");
  const [installError, setInstallError] = useState<string | null>(null);
  const [urlInstallOpen, setUrlInstallOpen] = useState(false);
  const [publishOpen, setPublishOpen] = useState(false);
  const [publishCapacity, setPublishCapacity] = useState("4");
  const [publishDescription, setPublishDescription] = useState("");
  const [publishPackage, setPublishPackage] = useState<
    Awaited<ReturnType<typeof select_app_pool_package>> | null
  >(null);
  const [capacityOpen, setCapacityOpen] = useState(false);
  const [additionalCapacity, setAdditionalCapacity] = useState("4");
  const [catalogApps, setCatalogApps] = useState<
    Awaited<ReturnType<typeof getCatalogApps>>
  >([]);
  const [capacityAppId, setCapacityAppId] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const installUrlInputRef = useRef<HTMLInputElement>(null);
  const installUrlButtonRef = useRef<HTMLButtonElement>(null);
  const installRunRef = useRef(false);
  const urlDownloadAbortRef = useRef<AbortController | null>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const apps = useAppsStore((state) => state.list);
  const owner = useAuthStore((state) => state.owner);
  const appIds = useAuthStore((state) => state.appIds);
  const operationBusy = useAppsStore((state) => state.operationBusy);
  const authorityPending = useAppsStore(isAuthorityPendingState);
  const appMutationBlocked = operationBusy || authorityPending;

  // Raw Neutron File/URL installation remains available internally but is
  // hidden from the normal Plasmon owner workflow.
  const showLowLevelInstallControls = false;
  const openTile = useWorkspaceStore((state) => state.openTile);
  const resetCurrentWorkspace = useWorkspaceStore(
    (state) => state.resetCurrentWorkspace,
  );

  useEffect(() => {
    if (!open) {
      urlDownloadAbortRef.current?.abort();
      urlDownloadAbortRef.current = null;
      return;
    }
    setQuery("");
    setInstallError(null);
    setInstallUrl("");
    setUrlInstallOpen(false);
    setPublishOpen(false);
    setPublishCapacity("4");
    setPublishDescription("");
    setPublishPackage(null);
    setCapacityOpen(false);
    setAdditionalCapacity("4");
    setCatalogApps([]);
    setCapacityAppId("");
    if (placement === "modal") {
      openerRef.current =
        document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;
      setTimeout(() => inputRef.current?.focus(), 0);
    }
  }, [open, placement]);

  useEffect(
    () => () => {
      urlDownloadAbortRef.current?.abort();
    },
    [],
  );

  useEffect(() => {
    if (open && urlInstallOpen) installUrlInputRef.current?.focus();
  }, [open, urlInstallOpen]);

  const close = (restoreFocus: boolean) => {
    const opener = openerRef.current;
    urlDownloadAbortRef.current?.abort();
    urlDownloadAbortRef.current = null;
    onClose?.();
    if (placement === "workspace") {
      setQuery("");
      setInstallError(null);
      setInstallUrl("");
      setUrlInstallOpen(false);
      setPublishOpen(false);
      setPublishCapacity("4");
      setPublishDescription("");
      setPublishPackage(null);
      setCapacityOpen(false);
      setAdditionalCapacity("4");
      setCatalogApps([]);
      setCapacityAppId("");
    } else if (restoreFocus && opener?.isConnected) {
      requestAnimationFrame(() => opener.focus());
    }
  };

  const visibleApps = useMemo(() => {
    if (owner) return apps;

    const allowed = new Set(appIds);
    return Object.fromEntries(
      Object.entries(apps).filter(([appId]) => allowed.has(appId)),
    ) as typeof apps;
  }, [apps, owner, appIds]);

  useEffect(() => {
    if (!open || owner) {
      setAvailableApps([]);
      return;
    }

    let cancelled = false;

    void getAvailableApps()
      .then((apps) => {
        if (!cancelled) setAvailableApps(apps);
      })
      .catch((error) => {
        if (!cancelled) {
          setAllocateError(
            error instanceof Error
              ? error.message
              : "Unable to load available apps.",
          );
        }
      });

    return () => {
      cancelled = true;
    };
  }, [open, owner, appIds]);

  useEffect(() => {
    if (!open || !owner || !capacityOpen) return;

    let cancelled = false;

    void getCatalogApps()
      .then((items) => {
        if (cancelled) return;

        setCatalogApps(items);
        setCapacityAppId((current) =>
          current &&
          items.some((item) => item.appId === current)
            ? current
            : (items[0]?.appId ?? ""),
        );
      })
      .catch((error) => {
        if (!cancelled) {
          setInstallError(
            error instanceof Error
              ? error.message
              : "Unable to load Element catalog.",
          );
        }
      });

    return () => {
      cancelled = true;
    };
  }, [open, owner, capacityOpen]);
  // Owners continue to use Neutron's physical app/tile launcher. Tenants
  // instead see one logical Element row, keeping workspace Tiles separate from
  // installation/Atom allocation.
  const entries = useMemo(
    () => (owner ? launcherEntriesFromApps(visibleApps, query) : []),
    [visibleApps, query, owner],
  );
  const tenantElements = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    if (!normalized) return availableApps;

    return availableApps.filter((app) =>
      [app.appId, app.name, app.description].some((value) =>
        value.toLocaleLowerCase().includes(normalized),
      ),
    );
  }, [availableApps, query]);

  const selectedCapacityApp = useMemo(
    () =>
      catalogApps.find((item) => item.appId === capacityAppId) ?? null,
    [catalogApps, capacityAppId],
  );
  const dependencyPlan = useMemo(() => {
    if (!owner) return null;
    try {
      return planAppRegistryDependencies(apps);
    } catch {
      return null;
    }
  }, [apps, owner]);

  if (!open) return null;

  const launch = (entry: LauncherEntry) => {
    openTile({
      appId: entry.appId,
      tileId: entry.tileId,
      title: workspaceTileTitle(entry.appName, entry.title),
      path: entry.path,
      icon: entry.icon,
    });
    close(true);
  };

  const appInstanceEntry = (
    appInstanceId: string,
    registry = useAppsStore.getState().list,
  ): LauncherEntry | null => {
    const registered = registry[appInstanceId];
    if (!registered) return null;

    return (
      launcherEntriesFromApps(
        { [appInstanceId]: registered } as typeof apps,
        "",
      )[0] ?? null
    );
  };

  const launchAppInstance = async (
    appInstanceId: string,
    appName: string,
  ): Promise<boolean> => {
    let entry = appInstanceEntry(appInstanceId);

    // Logical app discovery and physical registry loading are independent.
    // If allocation finishes first, refresh the committed app registry once
    // rather than failing the launch because the frontend store is stale.
    if (!entry) {
      try {
        const refreshedApps = await getApps();
        entry = appInstanceEntry(appInstanceId, refreshedApps);
      } catch (error) {
        setAllocateError(
          error instanceof Error
            ? error.message
            : `Unable to load ${appName}.`,
        );
        return false;
      }
    }

    if (!entry) {
      setAllocateError(
        `${appName} is installed, but its runtime tile is unavailable.`,
      );
      return false;
    }

    launch(entry);
    return true;
  };

  const activateTenantElement = async (
    app: (typeof availableApps)[number],
  ): Promise<void> => {
    // Open is only a workspace operation. Only Install calls the allocator, so
    // opening the same installed app repeatedly can create multiple Tiles while
    // all of them still reference the same physical app instance.
    if (app.appInstanceId !== null) {
      await launchAppInstance(app.appInstanceId, app.name);
      return;
    }
    if (allocateBusyAppId !== null) return;

    setAllocateBusyAppId(app.appId);
    setAllocateError(null);

    try {
      const appInstanceId = await allocateAppInstance(app.appId);
      if (appInstanceId === null) {
        setAllocateError(`${app.name} is temporarily unavailable.`);
        return;
      }

      // Reflect Install -> Open immediately. The appIds refresh performed by
      // allocateAppInstance causes the normal catalog effect to re-read the
      // same persisted installation mapping afterward.
      setAvailableApps((current) =>
        current.map((item) =>
          item.appId === app.appId ? { ...item, appInstanceId } : item,
        ),
      );
      await launchAppInstance(appInstanceId, app.name);
    } catch (error) {
      setAllocateError(
        error instanceof Error
          ? error.message
          : `Unable to install ${app.name}.`,
      );
    } finally {
      setAllocateBusyAppId(null);
    }
  };

  const installPackage = async (source: AppInstallSource) => {
    if (!owner) return;
    if (
      installRunRef.current ||
      useAppsStore.getState().operationBusy ||
      isAuthorityPendingState(useAppsStore.getState())
    ) return;
    installRunRef.current = true;
    setInstallSource(source.kind);
    setInstallError(null);
    try {
      const result = await install_app(source);
      if (result) {
        const entry = result.apps[result.appId];
        const tile = entry?.tiles[0];
        if (entry && tile) {
          openTile({
            appId: result.appId,
            tileId: tile.id,
            title: workspaceTileTitle(entry.name, tile.title),
            path: tile.path,
            icon: tile.icon,
          });
        }
      }
      close(true);
    } catch (error) {
      if (!quietInstallCancellation(error)) {
        const message = installErrorMessage(error);
        setInstallError(message);
        console.error(`Install package failed: ${message}`);
      }
    } finally {
      if (source.kind === "url") urlDownloadAbortRef.current = null;
      installRunRef.current = false;
      setInstallSource(null);
    }
  };

  const choosePublishPackage = async () => {
    try {
      const selected = await select_app_pool_package();
      setPublishPackage(selected);
      setPublishDescription(selected.description);
      setInstallError(null);
    } catch (error) {
      if (!quietInstallCancellation(error)) {
        setInstallError(installErrorMessage(error));
      }
    }
  };

  const publishElement = async () => {
    if (!owner || !publishPackage) return;

    const capacity = Number(publishCapacity);

    if (
      !Number.isSafeInteger(capacity) ||
      capacity < 1 ||
      capacity > 128
    ) {
      setInstallError("Capacity must be an integer from 1 through 128.");
      return;
    }

    if (
      installRunRef.current ||
      useAppsStore.getState().operationBusy ||
      isAuthorityPendingState(useAppsStore.getState())
    ) {
      return;
    }

    installRunRef.current = true;
    setInstallSource("pool");
    setInstallError(null);

    try {
      await install_app_pool({
        pkg: publishPackage.pkg,
        capacity,
        description: publishDescription.trim(),
      });

      close(true);
    } catch (error) {
      if (!quietInstallCancellation(error)) {
        const message = installErrorMessage(error);
        setInstallError(message);
        console.error(`Publish Element failed: ${message}`);
      }
    } finally {
      installRunRef.current = false;
      setInstallSource(null);
    }
  };
  const addElementCapacity = async () => {
    if (!owner || !capacityAppId) return;

    const capacity = Number(additionalCapacity);

    if (
      !Number.isSafeInteger(capacity) ||
      capacity < 1 ||
      capacity > 128
    ) {
      setInstallError(
        "Additional capacity must be an integer from 1 through 128.",
      );
      return;
    }

    if (
      installRunRef.current ||
      useAppsStore.getState().operationBusy ||
      isAuthorityPendingState(useAppsStore.getState())
    ) {
      return;
    }

    installRunRef.current = true;
    setInstallSource("capacity");
    setInstallError(null);

    try {
      await add_app_pool_capacity({
        appId: capacityAppId,
        additionalCapacity: capacity,
      });

      close(true);
    } catch (error) {
      if (!quietInstallCancellation(error)) {
        const message = installErrorMessage(error);
        setInstallError(message);
        console.error(`Add Element capacity failed: ${message}`);
      }
    } finally {
      installRunRef.current = false;
      setInstallSource(null);
    }
  };
  const installPackageFromUrl = () => {
    const abort = new AbortController();
    urlDownloadAbortRef.current?.abort();
    urlDownloadAbortRef.current = abort;
    void installPackage({
      kind: "url",
      signal: abort.signal,
      url: installUrl,
    });
  };

  const closeUrlInstall = (restoreFocus: boolean) => {
    urlDownloadAbortRef.current?.abort();
    urlDownloadAbortRef.current = null;
    setInstallError(null);
    setInstallUrl("");
    setUrlInstallOpen(false);
    if (restoreFocus) {
      requestAnimationFrame(() => installUrlButtonRef.current?.focus());
    }
  };

  const uninstallPackage = async (appId: string, appName: string) => {
    if (!owner) return;
    if (
      installRunRef.current ||
      useAppsStore.getState().operationBusy ||
      isAuthorityPendingState(useAppsStore.getState())
    ) return;
    const accepted = await requestAppUninstall({
      appId,
      appName,
      memoryIds: [],
    });
    if (!accepted) return;
    setInstallSource("uninstall");
    try {
      await uninstall_app(appId);
      close(true);
    } catch (error) {
      console.error("Uninstall package failed", error);
    } finally {
      setInstallSource(null);
    }
  };

  return (
    <>
      {placement === "modal" ? (
        <div
          aria-hidden="true"
          className="launcher-backdrop"
          onClick={() => close(true)}
        />
      ) : null}
      <div
        aria-label="App launcher"
        aria-modal={placement === "modal" ? "true" : undefined}
        className={`launcher launcher--${placement}`}
        data-tid={
          placement === "modal" ? "launcher" : "workspace-launcher"
        }
        onKeyDown={
          placement === "modal"
            ? (event) => {
                if (event.key === "Escape") {
                  event.preventDefault();
                  event.stopPropagation();
                  close(true);
                  return;
                }
                if (event.key === "Tab" && dialogRef.current) {
                  trapLauncherFocus(dialogRef.current, event);
                }
              }
            : undefined
        }
        ref={dialogRef}
        role={placement === "modal" ? "dialog" : "region"}
        tabIndex={placement === "modal" ? -1 : undefined}
      >
        <div className="launcher-search">
          <IoSearch aria-hidden="true" />
          <input
            aria-label={owner ? "Search app tiles" : "Search Elements"}
            ref={inputRef}
            data-tid={testId("launcher-search")}
            value={query}
            placeholder={owner ? "Search tiles" : "Search Elements"}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key !== "Enter") return;
              if (owner && entries[0]) launch(entries[0]);
              else if (!owner && tenantElements[0]) {
                void activateTenantElement(tenantElements[0]);
              }
            }}
          />
        </div>
        {placement === "modal" ? (
          <div className="launcher-actions launcher-actions--modal">
            <button
              type="button"
              className="launcher-action"
              data-tid={launcherSystemActions.resetWorkspace}
              onClick={() => {
                resetCurrentWorkspace();
                close(true);
              }}
            >
              <IoRefresh aria-hidden="true" />
              <span>Reset Current Workspace</span>
            </button>
          </div>
        ) : null}
        {owner ? (
          <>
            <button
              type="button"
              className="launcher-action"
              data-tid={testId("launcher-publish-element")}
              disabled={installSource !== null || appMutationBlocked}
              onClick={() => {
                setInstallError(null);
                setUrlInstallOpen(false);
                setCapacityOpen(false);
                setPublishOpen((current) => !current);
              }}
            >
              <IoAdd aria-hidden="true" />
              <span>Publish Element</span>
            </button>

            {publishOpen ? (
              <form
                aria-busy={installSource === "pool"}
                className="launcher-url-panel"
                noValidate
                onSubmit={(event) => {
                  event.preventDefault();
                  void publishElement();
                }}
              >
                <label>Element package</label>

                <div className="btn-actions">
                  <button
                    className="btn btn-sec"
                    disabled={
                      installSource !== null || appMutationBlocked
                    }
                    onClick={() => {
                      void choosePublishPackage();
                    }}
                    type="button"
                  >
                    {publishPackage
                      ? "Choose Different Package"
                      : "Choose Package"}
                  </button>
                </div>

                {publishPackage ? (
                  <div
                    style={{
                      display: "grid",
                      gap: "0.25rem",
                      width: "100%",
                      fontSize: "0.8rem",
                    }}
                  >
                    <strong>{publishPackage.fileName}</strong>
                    <span>Element: {publishPackage.name}</span>
                    <span>ID: {publishPackage.appId}</span>
                    <span>Version: {publishPackage.version}</span>
                  </div>
                ) : null}

                <label htmlFor={`${idPrefix}-publish-description`}>
                  Description
                </label>

                <textarea
                  id={`${idPrefix}-publish-description`}
                  data-tid={testId("launcher-publish-description")}
                  disabled={installSource !== null || appMutationBlocked}
                  placeholder="Optional description"
                  rows={3}
                  style={{
                    boxSizing: "border-box",
                    display: "block",
                    width: "100%",
                    minWidth: 0,
                    resize: "vertical",
                  }}
                  value={publishDescription}
                  onChange={(event) => {
                    setPublishDescription(event.target.value);
                    setInstallError(null);
                  }}
                />

                <label htmlFor={`${idPrefix}-publish-capacity`}>
                  Initial Atom capacity
                </label>

                <div className="launcher-url-row">
                  <div
                    className="launcher-url-input"
                    style={{
                      width: "7rem",
                      minWidth: "7rem",
                      flex: "0 0 7rem",
                    }}
                  >
                    <input
                      id={`${idPrefix}-publish-capacity`}
                      data-tid={testId("launcher-publish-capacity")}
                      disabled={
                        installSource !== null || appMutationBlocked
                      }
                      min="1"
                      max="128"
                      step="1"
                      type="number"
                      value={publishCapacity}
                      onChange={(event) => {
                        setPublishCapacity(event.target.value);
                        setInstallError(null);
                      }}
                      style={{
                        boxSizing: "border-box",
                        width: "100%",
                        minWidth: "100%",
                      }}
                    />
                  </div>
                </div>

                <div className="btn-actions">
                  <button
                    className="btn"
                    data-tid={testId("launcher-publish-submit")}
                    disabled={
                      !publishPackage ||
                      installSource !== null ||
                      appMutationBlocked
                    }
                    type="submit"
                  >
                    {installSource === "pool"
                      ? "Publishing..."
                      : "Publish Element"}
                  </button>

                  <button
                    className="btn btn-sec"
                    disabled={installSource === "pool"}
                    onClick={() => {
                      setPublishOpen(false);
                      setPublishPackage(null);
                      setInstallError(null);
                    }}
                    type="button"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            ) : null}
          </>
        ) : null}
        {owner ? (
          <>
            <button
              type="button"
              className="launcher-action"
              data-tid={testId("launcher-add-capacity")}
              disabled={installSource !== null || appMutationBlocked}
              onClick={() => {
                setInstallError(null);
                setUrlInstallOpen(false);
                setPublishOpen(false);
                setCapacityOpen((current) => !current);
              }}
            >
              <IoAdd aria-hidden="true" />
              <span>Add Capacity</span>
            </button>

            {capacityOpen ? (
              <form
                aria-busy={installSource === "capacity"}
                className="launcher-url-panel"
                noValidate
                onSubmit={(event) => {
                  event.preventDefault();
                  void addElementCapacity();
                }}
              >
                <label htmlFor={`${idPrefix}-capacity-element`}>
                  Element
                </label>

                <select
                  id={`${idPrefix}-capacity-element`}
                  data-tid={testId("launcher-capacity-element")}
                  disabled={
                    installSource !== null ||
                    appMutationBlocked ||
                    catalogApps.length === 0
                  }
                  style={{
                    boxSizing: "border-box",
                    width: "100%",
                    minWidth: 0,
                  }}
                  value={capacityAppId}
                  onChange={(event) => {
                    setCapacityAppId(event.target.value);
                    setInstallError(null);
                  }}
                >
                  {catalogApps.map((item) => (
                    <option key={item.appId} value={item.appId}>
                      {item.name} ({item.appId})
                    </option>
                  ))}
                </select>

                {selectedCapacityApp ? (
                  <div style={{ fontSize: "0.8rem" }}>
                    Current capacity: {selectedCapacityApp.capacity} Atoms
                  </div>
                ) : null}

                <label htmlFor={`${idPrefix}-additional-capacity`}>
                  Additional Atom capacity
                </label>

                <div className="launcher-url-row">
                  <div
                    className="launcher-url-input"
                    style={{
                      width: "7rem",
                      minWidth: "7rem",
                      flex: "0 0 7rem",
                    }}
                  >
                    <input
                      id={`${idPrefix}-additional-capacity`}
                      data-tid={testId("launcher-additional-capacity")}
                      disabled={
                        installSource !== null || appMutationBlocked
                      }
                      min="1"
                      max="128"
                      step="1"
                      type="number"
                      value={additionalCapacity}
                      onChange={(event) => {
                        setAdditionalCapacity(event.target.value);
                        setInstallError(null);
                      }}
                      style={{
                        boxSizing: "border-box",
                        width: "100%",
                        minWidth: "100%",
                      }}
                    />
                  </div>
                </div>

                <div className="btn-actions">
                  <button
                    className="btn"
                    disabled={
                      !capacityAppId ||
                      installSource !== null ||
                      appMutationBlocked
                    }
                    type="submit"
                  >
                    {installSource === "capacity"
                      ? "Adding Capacity..."
                      : "Add Capacity"}
                  </button>

                  <button
                    className="btn btn-sec"
                    disabled={installSource === "capacity"}
                    onClick={() => {
                      setCapacityOpen(false);
                      setInstallError(null);
                    }}
                    type="button"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            ) : null}
          </>
        ) : null}
        {urlInstallOpen ? (
          <form
            aria-busy={installSource === "url"}
            className="launcher-url-panel"
            id={`${idPrefix}-install-url-panel`}
            noValidate
            onKeyDown={(event) => {
              if (event.key !== "Escape") return;
              event.preventDefault();
              event.stopPropagation();
              closeUrlInstall(true);
            }}
            onSubmit={(event) => {
              event.preventDefault();
              installPackageFromUrl();
            }}
          >
            <label htmlFor={`${idPrefix}-install-url`}>
              App package URL
            </label>
            <div className="launcher-url-row">
              <div className="launcher-url-input">
                <IoLinkOutline aria-hidden="true" />
                <input
                  aria-describedby={
                    installError
                      ? `${idPrefix}-install-url-error`
                      : `${idPrefix}-install-url-help`
                  }
                  aria-invalid={installError ? "true" : undefined}
                  autoComplete="url"
                  data-tid={testId("launcher-install-url-input")}
                  disabled={installSource !== null || appMutationBlocked}
                  id={`${idPrefix}-install-url`}
                  onChange={(event) => {
                    setInstallUrl(event.target.value);
                    setInstallError(null);
                  }}
                  placeholder="https://example.com/app.v0.1.0.neutron"
                  ref={installUrlInputRef}
                  spellCheck={false}
                  type="url"
                  value={installUrl}
                />
              </div>
              <button
                className="btn launcher-url-submit"
                data-tid={testId("launcher-install-url-submit")}
                disabled={installSource !== null || appMutationBlocked}
                type="submit"
              >
                {installSource === "url" ? "Preparing..." : "Install"}
              </button>
              <button
                className="btn btn-sec launcher-url-cancel"
                data-tid={testId("launcher-install-url-cancel")}
                onClick={() => closeUrlInstall(true)}
                type="button"
              >
                Cancel
              </button>
            </div>
            {installError ? (
              <div
                className="launcher-install-error"
                data-tid={testId("launcher-install-url-error")}
                id={`${idPrefix}-install-url-error`}
                role="alert"
              >
                {installError}
              </div>
            ) : (
              <div
                className="launcher-url-help"
                id={`${idPrefix}-install-url-help`}
              >
                HTTPS package URL. You will review the same install request before
                anything changes.
              </div>
            )}
          </form>
        ) : installError ? (
          <div className="launcher-install-error" role="alert">
            {installError}
          </div>
        ) : null}
        <div className="launcher-results">
          {showLowLevelInstallControls && owner ? (
          <div className="launcher-tile-row launcher-install-entry">
            <div className="launcher-install-tile">
              {owner ? (
                <span aria-hidden="true" className="launcher-install-icon">
                  <IoAdd />
                </span>
              ) : null}
              {owner ? (
<div
                aria-label="Install app from"
                className="launcher-install-buttons"
                role="group"
              >
                <button
                  aria-label="Install app from File"
                  className="launcher-install-button"
            data-tid={testId(launcherSystemActions.installPackage)}
                  disabled={installSource !== null || appMutationBlocked}
                  onClick={() => {
                    closeUrlInstall(false);
                    void installPackage({ kind: "file" });
                  }}
                  type="button"
                >
                  <span>File</span>
                </button>
                <button
                  aria-controls={`${idPrefix}-install-url-panel`}
                  aria-expanded={urlInstallOpen}
                  aria-label="Install app from URL"
                  className={`launcher-install-button${urlInstallOpen ? " is-active" : ""}`}
            data-tid={testId(launcherSystemActions.installPackageUrl)}
                  disabled={installSource !== null || appMutationBlocked}
                  onClick={() => {
                    if (urlInstallOpen) closeUrlInstall(false);
                    else {
                      setInstallError(null);
                      setUrlInstallOpen(true);
                    }
                  }}
                  ref={installUrlButtonRef}
                  type="button"
                >
                  <span>URL</span>
                </button>
              </div>
              ) : null}
            </div>
          </div>
          ) : null}


          {!owner ? (
            <>
              {tenantElements.map((app) => {
                const installed = app.appInstanceId !== null;
                const installedEntry = installed
                  ? appInstanceEntry(app.appInstanceId!)
                  : null;
                const busy = allocateBusyAppId === app.appId;

                return (
                  <div
                    className="launcher-tile-row"
                    key={`element-${app.appId}`}
                  >
                    <button
                      type="button"
                      className="launcher-tile"
                      aria-label={`${installed ? "Open" : "Install"} ${app.name}`}
                      data-tid={testId(`launcher-element-${app.appId}`)}
                      data-state={installed ? "open" : "install"}
                      disabled={allocateBusyAppId !== null}
                      onClick={() => { void activateTenantElement(app); }}
                    >
                      {installedEntry ? (
                        <img src={installedEntry.icon} alt="" />
                      ) : (
                        <span aria-hidden="true" className="launcher-install-icon">
                          <IoAdd />
                        </span>
                      )}

                      <span
                        style={{
                          display: "flex",
                          flexDirection: "column",
                          gap: "0.15rem",
                          minWidth: 0,
                          textAlign: "left",
                        }}
                      >
                        <span className="launcher-tile-title">
                          {busy ? `Installing ${app.name}...` : app.name}
                        </span>
                        <span
                          style={{
                            fontSize: "0.75rem",
                            opacity: 0.72,
                            whiteSpace: "normal",
                            overflowWrap: "anywhere",
                            lineHeight: 1.25,
                          }}
                        >
                          {app.description ||
                            (installed ? "Installed" : "Install this Element")}
                        </span>
                        <span
                          style={{
                            fontSize: "0.7rem",
                            fontWeight: 600,
                            opacity: 0.8,
                          }}
                        >
                          {installed ? "Open" : "Install"}
                        </span>
                      </span>
                    </button>
                  </div>
                );
              })}
            </>
          ) : null}

          {allocateError ? (
            <div className="launcher-install-error" role="alert">
              {allocateError}
            </div>
          ) : null}

          {entries.map((entry) => {
            const impact = dependencyPlan
              ? appDependencyImpact(dependencyPlan, entry.appId)
              : null;
            const dependentNames = [
              ...new Set(
                (impact?.direct ?? []).map(({ consumer }) => consumer),
              ),
            ].map((consumer) => apps[consumer]?.name ?? consumer);
            const uninstallDisabled =
              installSource !== null ||
              appMutationBlocked ||
              dependencyPlan === null ||
              dependentNames.length > 0;
            const uninstallTitle =
              dependentNames.length > 0
                ? `Required by ${dependentNames.join(", ")}`
                : authorityPending
                  ? "Finish or discard the pending installation first"
                  : dependencyPlan === null
                    ? "Resolve app dependency metadata before uninstalling"
                    : `Uninstall ${entry.appName}`;
            return (
              <div
                className="launcher-tile-row"
                key={`${entry.appId}/${entry.tileId}`}
              >
                <button
                  type="button"
                  className="launcher-tile"
                  data-tid={testId(
                    `launcher-tile-${entry.appId}-${entry.tileId}`,
                  )}
                  onClick={() => launch(entry)}
                >
                  <img src={entry.icon} alt="" />
                  <span className="launcher-tile-title">{entry.title}</span>
                </button>
                {owner ? (
                  <button
                    type="button"
                    className="launcher-uninstall"
                    title={uninstallTitle}
                    aria-label={uninstallTitle}
                    disabled={uninstallDisabled}
                    onClick={() =>
                      void uninstallPackage(entry.appId, entry.appName)
                    }
                  >
                    <IoTrashOutline aria-hidden="true" />
                  </button>
                ) : null}
              </div>
            );
          })}
          {(owner ? entries.length === 0 : tenantElements.length === 0) ? (
            <div className="launcher-empty">
              {owner ? "No matching tiles" : "No matching Elements"}
            </div>
          ) : null}
        </div>
      </div>
    </>
  );
}

function trapLauncherFocus(
  dialog: HTMLElement,
  event: ReactKeyboardEvent<HTMLElement>,
): void {
  const focusable = [...dialog.querySelectorAll<HTMLElement>(
    'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
  )];
  if (focusable.length === 0) {
    event.preventDefault();
    dialog.focus();
    return;
  }
  const first = focusable[0]!;
  const last = focusable.at(-1)!;
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

function quietInstallCancellation(error: unknown): boolean {
  return (
    isAbortError(error) ||
    (error instanceof Error &&
      (error.message === "File picker cancelled" ||
        error.message === "User rejected" ||
        error.message === "Install request cancelled"))
  );
}

function installErrorMessage(error: unknown): string {
  const fallback = "The app package could not be prepared";
  const message = error instanceof Error ? error.message.trim() : fallback;
  if (!message) return fallback;
  return message.length <= 320 ? message : `${message.slice(0, 317)}...`;
}

function workspaceTileTitle(appName: string, tileTitle: string): string {
  return appName.trim().toLocaleLowerCase() ===
    tileTitle.trim().toLocaleLowerCase()
    ? tileTitle
    : `${appName}: ${tileTitle}`;
}
