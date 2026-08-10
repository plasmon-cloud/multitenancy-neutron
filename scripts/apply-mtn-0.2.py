#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text()
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    p.write_text(text.replace(old, new, 1))


def patch_service() -> None:
    path = "apps/kernel/backend/authorization/Service.mo"
    replace_once(path, 'import Nat64 "mo:core/Nat64";\n', 'import Nat64 "mo:core/Nat64";\nimport Nat8 "mo:core/Nat8";\n')
    p = ROOT / path
    text = p.read_text().replace('import IC "../aaa_interface";\n', '')
    text = text.replace(
        '        scopeElement : Types.AppScopeRef -> ?Text,\n        now : () -> Nat64,\n',
        '        scopeElement : Types.AppScopeRef -> ?Text,\n        freshRandom : () -> async* Blob,\n        now : () -> Nat64,\n',
    )
    text = text.replace('await IC.management.raw_rand()', 'await* freshRandom()')
    marker = '        public func revoke(\n'
    if 'public func release(' not in text:
        release = '''        public func release(\n            input : Types.ReleaseInput,\n            caller : Principal,\n        ) : Types.MutationResult {\n            if (caller == ANONYMOUS) return #err(#unauthenticated);\n            let ?lease = Map.get(leases, Text.compare, input.lease_id) else {\n                return #err(#denied);\n            };\n            let #principal(subjectPrincipal) = lease.subject;\n            if (subjectPrincipal != caller) return #err(#not_authorized);\n            ignore Map.remove(leases, Text.compare, input.lease_id);\n            appendAudit(\n                "release",\n                ?lease.grant_id,\n                ?lease.subject,\n                ?lease.consumer_scope,\n                ?lease.provider_scope,\n                ?lease.resource,\n            );\n            #ok;\n        };\n\n'''
        text = text.replace(marker, release + marker, 1)
    if 'register_provider' not in text:
        text = text.replace(
            '                release = func(input : Types.ReleaseInput) : () {\n                    releaseFromScope(consumerScope, input.lease_id);\n                };\n',
            '                release = func(input : Types.ReleaseInput) : () {\n                    releaseFromScope(consumerScope, input.lease_id);\n                };\n                register_provider = func(dispatch : Types.ProviderDispatch) : () {\n                    if (scopeActive(consumerScope)) {\n                        Map.add(\n                            providerDispatch,\n                            Text.compare,\n                            CapabilityScope.key(consumerScope),\n                            dispatch,\n                        );\n                    };\n                };\n',
            1,
        )
    text = text.replace(
        '            for (right in [#read, #write, #reshare].vals()) {\n',
        '            let allRights : [Types.ResourceRight] = [#read, #write, #reshare];\n            for (right in allRights.vals()) {\n',
    )
    old_hex = '''        func hex(value : Blob) : Text {\n            var result = "";\n            for (byte in value.vals()) {\n                let n = byte / 16;\n                let m = byte % 16;\n                result #= LOWER_HEX_DIGITS[Nat64.toNat(Nat64.fromNat(Nat8.toNat(n)))] #\n                    LOWER_HEX_DIGITS[Nat64.toNat(Nat64.fromNat(Nat8.toNat(m)))];\n            };\n            result;\n        };\n'''
    new_hex = '''        func hex(value : Blob) : Text {\n            var result = "";\n            for (byte in value.vals()) {\n                let natural = Nat8.toNat(byte);\n                result #= LOWER_HEX_DIGITS[natural / 16] #\n                    LOWER_HEX_DIGITS[natural % 16];\n            };\n            result;\n        };\n'''
    text = text.replace(old_hex, new_hex)
    p.write_text(text)


def patch_types() -> None:
    path = "apps/kernel/backend/authorization/Types.mo"
    p = ROOT / path
    text = p.read_text()
    if 'register_provider' not in text:
        text = text.replace(
            '        release : ReleaseInput -> ();\n',
            '        release : ReleaseInput -> ();\n        register_provider : ProviderDispatch -> ();\n',
            1,
        )
    p.write_text(text)


def patch_public_capabilities() -> None:
    path = "packages/neutron-motoko-capabilities/src/lib.mo"
    p = ROOT / path
    text = p.read_text()
    if 'public type AuthorizationV1' in text:
        return
    addition = '''module {\n    // MTN 0.2 resource-authorization contracts. AppScope is the existing\n    // Neutron installation identity; ResourceRef remains provider-defined.\n    public type AuthorizationAppScopeRefV1 = {\n        app_id : Text;\n        installation_uid : Nat64;\n    };\n    public type AuthorizationSubjectRefV1 = { #principal : Principal };\n    public type AuthorizationResourceRefV1 = {\n        namespace : Text;\n        resource_id : Text;\n        resource_type : Text;\n    };\n    public type AuthorizationAudienceV1 = {\n        #any_authenticated;\n        #principal : Principal;\n    };\n    public type AuthorizationRightV1 = { #read; #write; #reshare };\n    public type AuthorizationGrantV1 = {\n        grant_id : Text;\n        issuer_subject : AuthorizationSubjectRefV1;\n        issuer_scope : AuthorizationAppScopeRefV1;\n        provider_scope : AuthorizationAppScopeRefV1;\n        resource : AuthorizationResourceRefV1;\n        audience : AuthorizationAudienceV1;\n        consumer_element : ?Text;\n        rights : [AuthorizationRightV1];\n        created_at : Nat64;\n        expires_at : ?Nat64;\n        revoked_at : ?Nat64;\n        parent_grant_id : ?Text;\n        resource_authorization_epoch : Nat64;\n        max_redemptions : ?Nat;\n        redemption_count : Nat;\n    };\n    public type AuthorizationIssueOutputV1 = {\n        grant : AuthorizationGrantV1;\n        token : Text;\n    };\n    public type AuthorizationErrorV1 = {\n        #invalid_request;\n        #unauthenticated;\n        #not_authorized;\n        #denied;\n        #unavailable;\n    };\n    public type AuthorizationIssueResultV1 = {\n        #ok : AuthorizationIssueOutputV1;\n        #err : AuthorizationErrorV1;\n    };\n    public type AuthorizationLeaseV1 = {\n        lease_id : Text;\n        grant_id : Text;\n        subject : AuthorizationSubjectRefV1;\n        consumer_scope : AuthorizationAppScopeRefV1;\n        provider_scope : AuthorizationAppScopeRefV1;\n        resource : AuthorizationResourceRefV1;\n        rights : [AuthorizationRightV1];\n        issued_at : Nat64;\n        expires_at : Nat64;\n    };\n    public type AuthorizationContextV1 = {\n        grant_id : Text;\n        lease_id : Text;\n        subject : AuthorizationSubjectRefV1;\n        consumer_scope : AuthorizationAppScopeRefV1;\n        provider_scope : AuthorizationAppScopeRefV1;\n        resource : AuthorizationResourceRefV1;\n        rights : [AuthorizationRightV1];\n    };\n    public type AuthorizationCallInputV1 = {\n        lease_id : Text;\n        requested_right : AuthorizationRightV1;\n        operation : Text;\n        payload : Blob;\n    };\n    public type AuthorizationCallRequestV1 = {\n        authorization : AuthorizationContextV1;\n        operation : Text;\n        payload : Blob;\n    };\n    public type AuthorizationCallResultV1 = {\n        #ok : Blob;\n        #denied;\n        #provider_unavailable;\n    };\n    public type AuthorizationDelegateInputV1 = {\n        lease_id : Text;\n        audience : AuthorizationAudienceV1;\n        consumer_element : ?Text;\n        rights : [AuthorizationRightV1];\n        expires_at : ?Nat64;\n        max_redemptions : ?Nat;\n    };\n    public type AuthorizationV1 = {\n        call : AuthorizationCallInputV1 -> async* AuthorizationCallResultV1;\n        delegate : AuthorizationDelegateInputV1 -> async* AuthorizationIssueResultV1;\n        release : { lease_id : Text } -> ();\n        register_provider : (AuthorizationCallRequestV1 -> async* Blob) -> ();\n    };\n\n'''
    if not text.startswith('module {\n'):
        raise SystemExit('unexpected neutron-motoko-capabilities module header')
    p.write_text(addition + text[len('module {\n'):])


def patch_catalog() -> None:
    path = "packages/neutron-tools/src/capabilities/catalog.ts"
    replace_once(
        path,
        '  deferred_timers: Object.freeze({\n    api: CAPABILITY_API_VERSION,\n    declaration: null,\n  }),\n',
        '  deferred_timers: Object.freeze({\n    api: CAPABILITY_API_VERSION,\n    declaration: null,\n  }),\n  authorization: Object.freeze({\n    api: CAPABILITY_API_VERSION,\n    declaration: null,\n  }),\n',
    )


def patch_assembler() -> None:
    path = "packages/neutron-compiler/src/assemble.ts"
    old = '''    if (id === "deferred_timers") {\n      return `        deferred_timers = ${KERNEL_INIT}.deferred_timers_capability(${appScopeName(conf.id)});`;\n    }\n'''
    new = old + '''    if (id === "authorization") {\n      return `        authorization = ${KERNEL_INIT}.authorization_capability(${appScopeName(conf.id)});`;\n    }\n'''
    replace_once(path, old, new)


def patch_main() -> None:
    path = "apps/kernel/backend/main.mo"
    replace_once(
        path,
        'import AppCatalogMemory "./memory/app_catalog/v1";\n',
        'import AppCatalogMemory "./memory/app_catalog/v1";\nimport AuthorizationGrantsMemory "./memory/authorization_grants/v1";\nimport AuthorizationEpochsMemory "./memory/authorization_resource_epochs/v1";\nimport AuthorizationAuditMemory "./memory/authorization_audit/v1";\nimport AuthorizationService "./authorization/Service";\nimport AuthorizationTypes "./authorization/Types";\n',
    )
    replace_once(
        path,
        '            appCatalogMem : AppCatalogMemory.Mem,\n        runningDeploymentId : Text,\n',
        '            appCatalogMem : AppCatalogMemory.Mem,\n        authorizationGrantsMem : AuthorizationGrantsMemory.Mem,\n        authorizationEpochsMem : AuthorizationEpochsMemory.Mem,\n        authorizationAuditMem : AuthorizationAuditMemory.Mem,\n        runningDeploymentId : Text,\n',
    )
    old = '        let canisterId = Principal.toText(canisterPrincipal);\n\n'
    new = '''        let canisterId = Principal.toText(canisterPrincipal);\n\n        let authorization = AuthorizationService.Service(\n            authorizationGrantsMem,\n            authorizationEpochsMem,\n            authorizationAuditMem,\n            func(scope : CapabilityTypes.AppScope) : Bool {\n                if (not InstallMemory.scopeActive(\n                    mem.install,\n                    runningDeploymentId,\n                    scope,\n                )) return false;\n                switch (Map.get(\n                    appInstanceLifecycleMem.retired,\n                    Text.compare,\n                    scope.app_id,\n                )) {\n                    case (?true) false;\n                    case _ true;\n                };\n            },\n            func(\n                subject : AuthorizationTypes.SubjectRef,\n                scope : CapabilityTypes.AppScope,\n            ) : Bool {\n                let #principal(principal) = subject;\n                if (principal == Principal.fromText("2vxsx-fae")) return false;\n                if (Set.contains(mem.core.authorized, Principal.compare, principal)) {\n                    return true;\n                };\n                switch (Map.get(tenantsMem.grants, Principal.compare, principal)) {\n                    case null false;\n                    case (?apps) Array.any(\n                        apps,\n                        func(appId : Text) : Bool { appId == scope.app_id },\n                    );\n                };\n            },\n            func(scope : CapabilityTypes.AppScope) : ?Text {\n                switch (Map.get(\n                    appInstancesMem.instances,\n                    Text.compare,\n                    scope.app_id,\n                )) {\n                    case (?element) ?element;\n                    case null ?scope.app_id;\n                };\n            },\n            func() : async* Blob { await IC.management.raw_rand() },\n            nowNanos,\n        );\n\n'''
    replace_once(path, old, new)
    old_cap = '''        public func randomness_capability(\n            appScope : CapabilityTypes.AppScope,\n        ) : RandomnessTypes.Capability {\n            randomness.capability(appScope);\n        };\n\n'''
    new_cap = old_cap + '''        public func authorization_capability(\n            appScope : CapabilityTypes.AppScope,\n        ) : AuthorizationTypes.AuthorizationCapabilityV1 {\n            authorization.consumerCapability(appScope);\n        };\n\n'''
    replace_once(path, old_cap, new_cap)
    old_api_anchor = '''        public func scope_active(scope : CapabilityTypes.AppScope) : Bool {\n            InstallMemory.scopeActive(mem.install, runningDeploymentId, scope);\n        };\n\n'''
    new_api = old_api_anchor + '''        public func /*query:unauthorized*/kernel_authorization_capabilities(\n            (),\n        ) : AuthorizationTypes.CapabilityDiscovery {\n            authorization.discovery();\n        };\n\n        public func /*update:unauthorized*/kernel_authorization_issue(\n            input : AuthorizationTypes.IssueInput,\n            /*caller*/ caller : Principal,\n        ) : async* AuthorizationTypes.IssueResult {\n            await* authorization.issue(input, caller);\n        };\n\n        public func /*query:unauthorized*/kernel_authorization_list(\n            input : AuthorizationTypes.ListInput,\n            /*caller*/ caller : Principal,\n        ) : [AuthorizationTypes.AuthorizationGrant] {\n            authorization.list(input, caller);\n        };\n\n        public func /*query:unauthorized*/kernel_authorization_inspect(\n            input : AuthorizationTypes.InspectInput,\n        ) : ?AuthorizationTypes.GrantInspection {\n            authorization.inspect(input);\n        };\n\n        public func /*update:unauthorized*/kernel_authorization_redeem(\n            input : AuthorizationTypes.RedeemInput,\n            /*caller*/ caller : Principal,\n        ) : async* AuthorizationTypes.RedeemResult {\n            await* authorization.redeem(input, caller);\n        };\n\n        public func /*update:unauthorized*/kernel_authorization_release(\n            input : AuthorizationTypes.ReleaseInput,\n            /*caller*/ caller : Principal,\n        ) : AuthorizationTypes.MutationResult {\n            authorization.release(input, caller);\n        };\n\n        public func /*update:unauthorized*/kernel_authorization_revoke(\n            input : AuthorizationTypes.RevokeInput,\n            /*caller*/ caller : Principal,\n        ) : AuthorizationTypes.MutationResult {\n            authorization.revoke(input, caller);\n        };\n\n        public func /*update:unauthorized*/kernel_authorization_rotate_resource(\n            input : AuthorizationTypes.RotateResourceInput,\n            /*caller*/ caller : Principal,\n        ) : AuthorizationTypes.MutationResult {\n            authorization.rotateResource(input, caller);\n        };\n\n'''
    replace_once(path, old_api_anchor, new_api)


def patch_manifest() -> None:
    path = ROOT / "apps/kernel/neutron.json"
    data = json.loads(path.read_text())
    for name in [
        "memory_authorization_grants",
        "memory_authorization_resource_epochs",
        "memory_authorization_audit",
    ]:
        if name not in data["init_arg"]:
            idx = data["init_arg"].index("deployment_id")
            data["init_arg"].insert(idx, name)
    funcs = data["func"]
    additions = {
        "kernel_authorization_capabilities": {"type": "query", "async": False, "allow": "unauthorized"},
        "kernel_authorization_issue": {"type": "update", "async": "async*", "arg": ["caller"], "allow": "unauthorized"},
        "kernel_authorization_list": {"type": "query", "async": False, "arg": ["caller"], "allow": "unauthorized"},
        "kernel_authorization_inspect": {"type": "query", "async": False, "allow": "unauthorized"},
        "kernel_authorization_redeem": {"type": "update", "async": "async*", "arg": ["caller"], "allow": "unauthorized"},
        "kernel_authorization_release": {"type": "update", "async": False, "arg": ["caller"], "allow": "unauthorized"},
        "kernel_authorization_revoke": {"type": "update", "async": False, "arg": ["caller"], "allow": "unauthorized"},
        "kernel_authorization_rotate_resource": {"type": "update", "async": False, "arg": ["caller"], "allow": "unauthorized"},
    }
    for key, value in additions.items():
        funcs.setdefault(key, value)
    memory = data["memory"]
    memory.setdefault("authorization_grants", {"version": 1, "schemas": {"1": {"src": "memory/authorization_grants/v1.mo"}}, "migrations": []})
    memory.setdefault("authorization_resource_epochs", {"version": 1, "schemas": {"1": {"src": "memory/authorization_resource_epochs/v1.mo"}}, "migrations": []})
    memory.setdefault("authorization_audit", {"version": 1, "schemas": {"1": {"src": "memory/authorization_audit/v1.mo"}}, "migrations": []})
    path.write_text(json.dumps(data, indent=2) + "\n")


def patch_test_runner() -> None:
    path = "apps/kernel/test/motoko/run.ts"
    replace_once(
        path,
        '  "app_instance_allocation_test.mo",\n',
        '  "app_instance_allocation_test.mo",\n  "authorization_service_test.mo",\n',
    )


def patch_ci() -> None:
    path = ".github/workflows/kernel-ci.yml"
    replace_once(
        path,
        '      - version-0.1.0\n',
        '      - version-0.1.0\n      - version-0.2.0\n',
    )


def main() -> None:
    patch_types()
    patch_service()
    patch_public_capabilities()
    patch_catalog()
    patch_assembler()
    patch_main()
    patch_manifest()
    patch_test_runner()
    patch_ci()


if __name__ == "__main__":
    main()
