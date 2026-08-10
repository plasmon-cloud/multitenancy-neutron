#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/backend/authorization/Service.mo")
text = p.read_text()
if 'import List "mo:core/List";' not in text:
    text = text.replace(
        'import Iter "mo:core/Iter";\n',
        'import Iter "mo:core/Iter";\nimport List "mo:core/List";\n',
        1,
    )

old = '''            var result : [Types.AuthorizationGrant] = [];\n            for ((_, stored) in Map.entries(grantsMem.grants)) {\n                if (\n                    CapabilityScope.equal(stored.grant.issuer_scope, issuerScope) and\n                    stored.grant.issuer_subject == currentSubject\n                ) {\n                    result := Array.concat(result, [stored.grant]);\n                };\n            };\n            result;\n'''
new = '''            let result = List.empty<Types.AuthorizationGrant>();\n            for ((_, stored) in Map.entries(grantsMem.grants)) {\n                if (\n                    CapabilityScope.equal(stored.grant.issuer_scope, issuerScope) and\n                    stored.grant.issuer_subject == currentSubject\n                ) {\n                    List.add(result, stored.grant);\n                };\n            };\n            List.toArray(result);\n'''
if old not in text:
    raise SystemExit("listFromScope collection target missing")
text = text.replace(old, new, 1)

old = '''        func normalizeRights(\n            rights : [Types.ResourceRight],\n        ) : [Types.ResourceRight] {\n            var result : [Types.ResourceRight] = [];\n            let allRights : [Types.ResourceRight] = [#read, #write, #reshare];\n            for (right in allRights.vals()) {\n                if (hasRight(rights, right)) result := Array.concat(result, [right]);\n            };\n            result;\n        };\n'''
new = '''        func normalizeRights(\n            rights : [Types.ResourceRight],\n        ) : [Types.ResourceRight] {\n            let allRights : [Types.ResourceRight] = [#read, #write, #reshare];\n            Array.filter<Types.ResourceRight>(\n                allRights,\n                func(right : Types.ResourceRight) : Bool {\n                    hasRight(rights, right);\n                },\n            );\n        };\n'''
if old not in text:
    raise SystemExit("normalizeRights collection target missing")
text = text.replace(old, new, 1)

p.write_text(text)
