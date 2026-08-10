#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/backend/authorization/Service.mo")
text = p.read_text()

old = '''            let lease : Types.AuthorizationLease = {\n                lease_id = leaseId;\n                grant_id = grant.grant_id;\n                subject;\n                consumer_scope = input.consumer_scope;\n                provider_scope = grant.provider_scope;\n                resource = grant.resource;\n                rights = grant.rights;\n                issued_at = issuedAt;\n                expires_at = issuedAt + LEASE_LIFETIME_NS;\n            };\n'''
new = '''            let nominalLeaseExpiry = issuedAt + LEASE_LIFETIME_NS;\n            let effectiveLeaseExpiry = switch (grant.expires_at) {\n                case (?grantExpiry) {\n                    if (grantExpiry < nominalLeaseExpiry) grantExpiry\n                    else nominalLeaseExpiry;\n                };\n                case null nominalLeaseExpiry;\n            };\n            let lease : Types.AuthorizationLease = {\n                lease_id = leaseId;\n                grant_id = grant.grant_id;\n                subject;\n                consumer_scope = input.consumer_scope;\n                provider_scope = grant.provider_scope;\n                resource = grant.resource;\n                rights = grant.rights;\n                issued_at = issuedAt;\n                expires_at = effectiveLeaseExpiry;\n            };\n'''
if old in text:
    text = text.replace(old, new, 1)

old = '''            ?{\n                grant_id = grant.grant_id;\n                resource = grant.resource;\n                consumer_element = grant.consumer_element;\n                rights = grant.rights;\n                expires_at = grant.expires_at;\n                revoked = grant.revoked_at != null or not grantEpochCurrent(grant);\n            };\n'''
new = '''            ?{\n                grant_id = grant.grant_id;\n                resource = grant.resource;\n                consumer_element = grant.consumer_element;\n                rights = grant.rights;\n                expires_at = grant.expires_at;\n                revoked = effectivelyRevoked(grant);\n            };\n'''
if old in text:
    text = text.replace(old, new, 1)

old = '''        func resourceKey(\n            providerScope : Types.AppScopeRef,\n            resource : Types.ResourceRef,\n        ) : Text {\n            CapabilityScope.key(providerScope) # "\\00" #\n            resource.namespace # "\\00" # resource.resource_id # "\\00" #\n            resource.resource_type;\n        };\n'''
new = '''        func resourceKey(\n            providerScope : Types.AppScopeRef,\n            resource : Types.ResourceRef,\n        ) : Text {\n            // Length-prefix opaque provider fields so embedded separators can\n            // never alias a different exact ResourceRef.\n            CapabilityScope.key(providerScope) # "\\00" #\n            Nat.toText(resource.namespace.size()) # ":" # resource.namespace #\n            Nat.toText(resource.resource_id.size()) # ":" # resource.resource_id #\n            Nat.toText(resource.resource_type.size()) # ":" # resource.resource_type;\n        };\n'''
if old in text:
    text = text.replace(old, new, 1)
    if 'import Nat "mo:core/Nat";' not in text:
        text = text.replace('import Map "mo:core/Map";\n', 'import Map "mo:core/Map";\nimport Nat "mo:core/Nat";\n', 1)

marker = '''        func grantEpochCurrent(grant : Types.AuthorizationGrant) : Bool {\n'''
helper = '''        func effectivelyRevoked(grant : Types.AuthorizationGrant) : Bool {\n            if (grant.revoked_at != null or not grantEpochCurrent(grant)) return true;\n            var current = grant;\n            var depth : Nat = 0;\n            label ancestry loop {\n                switch (current.parent_grant_id) {\n                    case null return false;\n                    case (?parentId) {\n                        if (depth >= MAX_ANCESTRY_DEPTH) return true;\n                        let ?parentStored = Map.get(\n                            grantsMem.grants,\n                            Text.compare,\n                            parentId,\n                        ) else return true;\n                        let parent = parentStored.grant;\n                        if (parent.revoked_at != null or not grantEpochCurrent(parent)) {\n                            return true;\n                        };\n                        current := parent;\n                        depth += 1;\n                        continue ancestry;\n                    };\n                };\n            };\n        };\n\n'''
if helper not in text:
    text = text.replace(marker, helper + marker, 1)

# Keep code-facing terminology on the repository name; mtn2 remains only the
# externally specified bearer-token prefix.
text = text.replace("MTN 0.2", "multitenancy-neutron 0.2")

p.write_text(text)
