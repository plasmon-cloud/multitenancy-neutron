import { expect, test } from "bun:test";

test("reviewed capability package exports leaf types only", async () => {
  const source = await Bun.file(
    new URL("../src/lib.mo", import.meta.url),
  ).text();

  expect(source).not.toMatch(/^\s*import\b/m);
  expect(source).not.toMatch(/\b(?:AppScope|AppInstance|Adapter)\b/);
  expect(source).not.toMatch(/\b(?:actor|class|public\s+func)\b/);
  expect(source).not.toMatch(/\b(?:cyclesAdd|management_canister|raw_rand)\b/);

  const authorizationTypes = [
    "AuthorizationSubjectV1",
    "AuthorizationScopeV1",
    "AuthorizationResourceV1",
    "AuthorizationAudienceV1",
    "AuthorizationRightV1",
    "AuthorizationGrantV1",
    "AuthorizationIssueInputV1",
    "AuthorizationIssueOutputV1",
    "AuthorizationIssueResultV1",
    "AuthorizationMutationResultV1",
    "AuthorizationLeaseV1",
    "AuthorizationContextV1",
    "AuthorizationCallInputV1",
    "AuthorizationCallRequestV1",
    "AuthorizationCallResultV1",
    "AuthorizationDelegateInputV1",
    "AuthorizationV1",
  ];
  for (const typeName of authorizationTypes) {
    expect(source).toContain(`public type ${typeName}`);
  }

  const authorizationSurface = source.slice(
    source.indexOf("public type AuthorizationSubjectV1"),
    source.indexOf("public type DeferredTimerPhaseV1"),
  );
  expect(authorizationSurface).not.toMatch(
    /\b(?:secret_hash|StoredGrant|memory_authorization|StableMemory|Region|management_canister|raw_rand)\b/,
  );
  expect(authorizationSurface).not.toContain("authorization_capability");
  expect(authorizationSurface.match(/\btoken\s*:/g)).toHaveLength(1);

  expect(
    authorizationSurface.match(
      /public type AuthorizationScopeV1 = \{([\s\S]*?)\n    \};/,
    )?.[1],
  ).toBe("\n        app_id : Text;\n        installation_uid : Nat64;");

  const issueInput = authorizationSurface.match(
    /public type AuthorizationIssueInputV1 = \{([\s\S]*?)\n    \};/,
  )?.[1] ?? "";
  expect(issueInput).toContain("resource : AuthorizationResourceV1");
  expect(issueInput).not.toMatch(/\b(?:provider_scope|issuer_scope|consumer_scope)\b/);

  const delegateInput = authorizationSurface.match(
    /public type AuthorizationDelegateInputV1 = \{([\s\S]*?)\n    \};/,
  )?.[1] ?? "";
  expect(delegateInput).toContain("lease_id : Text");
  expect(delegateInput).not.toMatch(
    /\b(?:provider_scope|issuer_scope|consumer_scope|resource)\b/,
  );

  const callInput = authorizationSurface.match(
    /public type AuthorizationCallInputV1 = \{([\s\S]*?)\n    \};/,
  )?.[1] ?? "";
  const callInputFields = [
    ...callInput.matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(callInputFields).toEqual([
    "lease_id",
    "requested_right",
    "operation",
    "payload",
  ]);
  expect(callInput).not.toMatch(/\b(?:provider_scope|resource|consumer_scope)\b/);

  const authorizationHandle = authorizationSurface.match(
    /public type AuthorizationV1 = \{([\s\S]*?)\n    \};/,
  )?.[1] ?? "";
  const authorizationHandleFields = [
    ...authorizationHandle.matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(authorizationHandleFields).toEqual([
    "issue",
    "list",
    "revoke",
    "rotate_resource",
    "register_provider",
    "call",
    "delegate",
    "release",
  ]);
  expect(authorizationHandle).not.toMatch(/\b(?:scope|factory|kernel)\s*:/i);

  expect(source).toContain("public type DeferredTimersV1");
  expect(source).toContain("callback : () -> ();");
  expect(source).toContain("public type BackendCallsV1");
  expect(
    source.match(/public type BackendCallRequestV1 = \{([\s\S]*?)\};/)?.[1],
  ).toContain("cycles : Nat");
  expect(source).toContain("public type RandomnessV1");
  expect(source).toContain("public type ChainKeyAlgorithmV1");
  expect(source).toContain("public type ChainKeyMessageFormatV1");
  expect(source).toContain("public type ChainKeyPublicKeyV1");
  expect(source).toContain("public type ChainKeySignatureV1");
  expect(source).toContain("public type ChainKeySigningErrorV1");
  expect(source).toContain("public type ChainKeySigningV1");
  expect(source).toContain("public type StableStoreConditionV1");
  expect(source).toContain("public type StableStoreCursorV1");
  expect(source).toContain("public type StableStoreEntryV1");
  expect(source).toContain("public type StableStoreErrorV1");
  expect(source).toContain("public type StableStoreV1");
  expect(source).toContain("public type HttpsOutcallRequestV1");
  expect(source).toContain("public type HttpsOutcallErrorV1");
  expect(source).toContain("public type HttpsOutcallsV1");
  expect(source).toContain("public type VetKeysPublicV1");
  expect(source).toContain("public type CertifiedAssetsV2");
  expect(source).not.toContain("InitializingCertifiedAssetsV2");
  expect(source).not.toContain("InitializeSingleton");
  expect(source).not.toContain("CertifiedAssetPutV1");
  expect(source).not.toContain("CertifiedAssetDeleteV1");
  expect(source).not.toContain("CertifiedAssetsErrorV1");
  expect(source).not.toContain("CertifiedAssetsUsageV1");
  expect(source).not.toContain("CertifiedAssetsResultV1");
  expect(source).not.toContain("CertifiedAssetsV1");
  expect(source).toContain("public type PublicIngressCyclesV1");
  expect(source).toContain("public type HttpPostUpdateHandlerRequestV1");
  expect(source).toContain("public type HttpPostUpdateHandlerResponseV1");
  expect(source).not.toMatch(/HttpsOutcallsV1[\s\S]*(?:cyclesAdd|management_canister|AppScope)/);
  const chainKeySurface = source.slice(
    source.indexOf("public type ChainKeyAlgorithmV1"),
    source.indexOf("public type HttpsOutcallMethodV1"),
  );
  expect(chainKeySurface).toContain(
    "#neutron_app_assertion_v1",
  );
  expect(chainKeySurface).toContain(
    "public_key : Text -> async* ChainKeyPublicKeyResultV1",
  );
  expect(chainKeySurface).toContain(
    "sign_assertion : ChainKeySignAssertionRequestV1 -> async* ChainKeySignatureResultV1",
  );
  expect(chainKeySurface).not.toMatch(
    /\b(?:derivation_path|key_name|chain_code|message_hash|sign_hash|aux)\b/,
  );
  expect(chainKeySurface).not.toMatch(/\bsign\s*:/);
  expect(chainKeySurface).not.toContain("#rate_limited");
  expect(chainKeySurface).not.toContain("#cycle_limited");
  expect(chainKeySurface).toContain("#cost_too_high");
  expect(chainKeySurface.match(/public type ChainKeySignAssertionRequestV1 = \{([\s\S]*?)\};/)?.[1])
    .toBe("\n        slot : Text;\n        assertion : Blob;\n    ");

  const stableStoreSurface = source.slice(
    source.indexOf("public type StableStoreConditionV1"),
    source.indexOf("public type PublicIngressRequestV1"),
  );
  const stableStoreDeclarations = stableStoreSurface.replace(/\/\/.*$/gm, "");
  expect(stableStoreSurface).toContain(
    "cursor : ?StableStoreCursorV1",
  );
  expect(stableStoreSurface).toContain(
    "clear_page : StableStoreClearPageRequestV1 -> StableStoreClearPageResultV1",
  );
  expect(stableStoreDeclarations).not.toMatch(
    /\b(?:AppScope|installation_uid|Region|StableMemory|offset|address)\b/,
  );
  expect(stableStoreSurface.match(/\bnamespace_uid\s*:/g)).toHaveLength(1);
  expect(stableStoreSurface).not.toContain("#rate_limited");

  const publicIngressCyclesSurface = source.match(
    /public type PublicIngressCyclesV1 = \{([\s\S]*?)\};/,
  )?.[1];
  expect(publicIngressCyclesSurface).toBe(
    "\n        available : () -> Nat;\n        request : Nat -> ();\n    ",
  );
  expect(publicIngressCyclesSurface).not.toMatch(
    /\b(?:Cycles|accept|add|balance|transfer)\b/,
  );

  const randomnessSurface = source.slice(
    source.indexOf("public type RandomnessErrorV1"),
    source.indexOf("public type ChainKeyAlgorithmV1"),
  );
  expect(randomnessSurface).not.toContain("#rate_limited");

  const httpsSurface = source.slice(
    source.indexOf("public type HttpsOutcallMethodV1"),
    source.indexOf("public type VetKeySlotStatusV1"),
  );
  expect(httpsSurface).not.toContain("#rate_limited");
  expect(httpsSurface).not.toContain("#cycle_limited");
  expect(httpsSurface).toContain("#cost_too_high");

  const vetkeysSurface = source.slice(
    source.indexOf("public type VetKeySlotStatusV1"),
    source.indexOf("public type Locator"),
  );
  expect(vetkeysSurface).not.toContain("#rate_limited");
  expect(vetkeysSurface).toContain("total_derivations : Nat");
  expect(vetkeysSurface).not.toContain("recent_derivations");

  const certifiedAssetsSurface = source.slice(
    source.indexOf("public type Locator"),
    source.indexOf("public type StableStoreConditionV1"),
  );
  const certifiedAssetsDeclarations = certifiedAssetsSurface.replace(
    /\/\/.*$/gm,
    "",
  );
  const expectedTypes = [
    "Locator",
    "Target",
    "Condition",
    "PublicationPresentation",
    "StageTarget",
    "BodySource",
    "BatchOperation",
    "PresentRequirement",
    "CommitBatchInput",
    "Limits",
    "CollectionKind",
    "CollectionInfo",
    "ScopeInfo",
    "StageGeometry",
    "RecordIdentity",
    "CasIdentity",
    "DeletedIdentity",
    "StageIdentity",
    "BeginStageInput",
    "BeginStageOk",
    "PutChunkInput",
    "StageProgress",
    "StageTerminal",
    "LifecycleOutcome",
    "StageStatus",
    "ChunkOk",
    "PutReceipt",
    "DeleteReceipt",
    "OperationReceipt",
    "BatchReceipt",
    "RecordStatus",
    "Reclaimed",
    "MaintenancePageOk",
    "UsageCounters",
    "Usage",
    "Error",
    "ScopeInfoResult",
    "BeginStageResult",
    "ChunkResult",
    "StageStatusResult",
    "CommitBatchResult",
    "RecordStatusResult",
    "MaintenancePageResult",
    "UsageResult",
    "Result",
    "CertifiedAssetsV2",
  ];
  for (const typeName of expectedTypes) {
    expect(certifiedAssetsSurface).toContain(`public type ${typeName}`);
  }
  expect(certifiedAssetsDeclarations).not.toMatch(
    /\b(?:AppScope|installation_uid|canister|host|mount|path|headers|content_type|clear_mount)\s*:/,
  );
  expect(certifiedAssetsDeclarations).not.toMatch(/\basync\*?\b/);
  expect(certifiedAssetsDeclarations).not.toMatch(
    /\b(?:files|wagyu|public_candid|singleton|template|pinned_lengths|unordered|accepted_bitmap|client_token|block_lengths)\b/i,
  );

  const collectionKinds = [
    ...(
      source.match(/public type CollectionKind = \{([\s\S]*?)\n    \};/)?.[1] ??
      ""
    ).matchAll(/#(\w+)/g),
  ].map((match) => match[1]);
  expect(collectionKinds).toEqual([
    "publication",
    "immutable_blob",
    "mutable_blob",
  ]);

  const locatorKinds = [
    ...(
      source.match(/public type Locator = \{([\s\S]*?)\n    \};/)?.[1] ?? ""
    ).matchAll(/#(\w+)/g),
  ].map((match) => match[1]);
  expect(locatorKinds).toEqual([
    "publication",
    "body_sha256",
    "key32",
    "exact_path",
  ]);

  const stageTargetKinds = [
    ...(
      source.match(/public type StageTarget = \{([\s\S]*?)\n    \};/)?.[1] ??
      ""
    ).matchAll(/#(\w+)/g),
  ].map((match) => match[1]);
  expect(stageTargetKinds).toEqual([
    "allocate_publication",
    "derive_body_sha256",
  ]);

  const beginStageFields = [
    ...(
      source.match(/public type BeginStageInput = \{([\s\S]*?)\n    \};/)?.[1] ??
      ""
    ).matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(beginStageFields).toEqual(["nonce", "target", "expected_bytes"]);

  const batchOperationSurface = source.slice(
    source.indexOf("public type BatchOperation"),
    source.indexOf("public type PresentRequirement"),
  );
  expect(batchOperationSurface).not.toContain("presentation");
  expect(
    source.match(/public type StageTarget = \{([\s\S]*?)\n    \};/)?.[1],
  ).toContain("presentation : PublicationPresentation");

  const stageGeometryFields = [
    ...(
      source.match(/public type StageGeometry = \{([\s\S]*?)\n    \};/)?.[1] ?? ""
    ).matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(stageGeometryFields).toEqual([
    "block_bytes",
    "block_count",
    "expected_bytes",
  ]);

  const stageProgressFields = [
    ...(
      source.match(/public type StageProgress = \{([\s\S]*?)\n    \};/)?.[1] ??
      ""
    ).matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(stageProgressFields).toEqual(["next_block_index", "block_hashes"]);

  expect(
    source.match(/public type LifecycleOutcome = \{([\s\S]*?)\n    \};/)?.[1],
  ).toBe("\n        committed : RecordIdentity;");
  expect(certifiedAssetsSurface).toContain("#inline : Blob");
  expect(certifiedAssetsSurface).toContain("body : Blob");

  const limitsFields = [
    ...(
      source.match(/public type Limits = \{([\s\S]*?)\n    \};/)?.[1] ?? ""
    ).matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(limitsFields).toEqual([
    "entries",
    "committed_bytes",
    "object_bytes",
    "staged_bytes",
    "pending_stages",
    "batch_operations",
    "batch_bytes",
    "general_receipts",
    "revocation_lanes",
  ]);

  const errorTags = [
    ...(
      source.match(/public type Error = \{([\s\S]*?)\n    \};/)?.[1] ?? ""
    ).matchAll(/#(\w+)/g),
  ].map((match) => match[1]);
  expect(errorTags).toEqual([
    "invalid",
    "stale_scope",
    "stale_generation",
    "disabled",
    "frozen",
    "not_found",
    "retired_key",
    "conflict",
    "quota",
    "receipt_full",
    "aborted",
    "expired",
    "incomplete",
    "not_ready",
    "generation_exhausted",
    "revision_exhausted",
    "low_cycles",
    "busy",
  ]);

  const handleFields = [
    ...(
      source.match(
        /public type CertifiedAssetsV2 = \{([\s\S]*?)\n    \};/,
      )?.[1] ?? ""
    ).matchAll(/^\s*(\w+)\s*:/gm),
  ].map((match) => match[1]);
  expect(handleFields).toEqual([
    "scope_info",
    "begin_stage",
    "put_chunk",
    "stage_status",
    "abort_stage",
    "commit_batch",
    "record_status",
    "maintenance_page",
    "usage",
  ]);

});
