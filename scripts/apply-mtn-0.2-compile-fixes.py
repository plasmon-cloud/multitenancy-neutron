#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/backend/authorization/Service.mo")
text = p.read_text()
text = text.replace(
    '    let ANONYMOUS = Principal.fromText("2vxsx-fae");\n',
    '    let ANONYMOUS_TEXT = "2vxsx-fae";\n',
    1,
)
text = text.replace('caller == ANONYMOUS', 'isAnonymous(caller)')
text = text.replace('principal != ANONYMOUS', 'not isAnonymous(principal)')
marker = '''        func audienceAllows(\n'''
helper = '''        func isAnonymous(principal : Principal) : Bool {\n            Principal.toText(principal) == ANONYMOUS_TEXT;\n        };\n\n'''
if helper not in text:
    text = text.replace(marker, helper + marker, 1)

start = text.index('        func grantUsable(')
end = text.index('        func grantEpochCurrent(', start)
replacement = '''        func grantUsable(grant : Types.AuthorizationGrant) : Bool {\n            if (\n                grant.revoked_at != null or\n                isExpired(grant.expires_at) or\n                not grantEpochCurrent(grant) or\n                not scopeActive(grant.provider_scope)\n            ) return false;\n            ancestryUsable(grant, grant, 0);\n        };\n\n        func ancestryUsable(\n            current : Types.AuthorizationGrant,\n            original : Types.AuthorizationGrant,\n            depth : Nat,\n        ) : Bool {\n            switch (current.parent_grant_id) {\n                case null true;\n                case (?parentId) {\n                    if (depth >= MAX_ANCESTRY_DEPTH) return false;\n                    let ?parentStored = Map.get(\n                        grantsMem.grants,\n                        Text.compare,\n                        parentId,\n                    ) else return false;\n                    let parent = parentStored.grant;\n                    if (\n                        parent.revoked_at != null or\n                        isExpired(parent.expires_at) or\n                        not grantEpochCurrent(parent) or\n                        not resourceEqual(parent.resource, original.resource) or\n                        not CapabilityScope.equal(\n                            parent.provider_scope,\n                            original.provider_scope,\n                        )\n                    ) return false;\n                    ancestryUsable(parent, original, depth + 1);\n                };\n            };\n        };\n\n        func effectivelyRevoked(grant : Types.AuthorizationGrant) : Bool {\n            if (grant.revoked_at != null or not grantEpochCurrent(grant)) {\n                return true;\n            };\n            ancestryRevoked(grant, 0);\n        };\n\n        func ancestryRevoked(\n            current : Types.AuthorizationGrant,\n            depth : Nat,\n        ) : Bool {\n            switch (current.parent_grant_id) {\n                case null false;\n                case (?parentId) {\n                    if (depth >= MAX_ANCESTRY_DEPTH) return true;\n                    let ?parentStored = Map.get(\n                        grantsMem.grants,\n                        Text.compare,
                        parentId,\n                    ) else return true;\n                    let parent = parentStored.grant;\n                    if (\n                        parent.revoked_at != null or\n                        not grantEpochCurrent(parent)\n                    ) return true;\n                    ancestryRevoked(parent, depth + 1);\n                };\n            };\n        };\n\n'''
text = text[:start] + replacement + text[end:]
p.write_text(text)
