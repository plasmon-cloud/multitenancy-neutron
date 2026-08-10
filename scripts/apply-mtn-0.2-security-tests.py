#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/test/motoko/authorization_service_test.mo")
text = p.read_text()

old = '''var clock : Nat64 = 1_000_000_000_000;\nvar entropyCounter : Nat8 = 1;\nlet active = Map.empty<Text, Bool>();\n'''
new = '''var clock : Nat64 = 1_000_000_000_000;\nvar entropyCounter : Nat8 = 1;\nvar freshRandomHook : ?(() -> async* ()) = null;\nlet active = Map.empty<Text, Bool>();\nlet owners = Map.empty<Text, Principal>();\n'''
if old not in text:
    raise SystemExit("test state anchor missing")
text = text.replace(old, new, 1)

anchor = '''for (value in [\n    aliceProvider,\n    aliceOtherProvider,\n    bobConsumer,\n    bobSibling,\n    bobConsumerTwin,\n    aliceConsumer,\n].vals()) {\n    Map.add(active, Text.compare, scopeKey(value), true);\n};\n'''
addition = anchor + '''Map.add(owners, Text.compare, scopeKey(aliceProvider), alice);\nMap.add(owners, Text.compare, scopeKey(aliceOtherProvider), alice);\nMap.add(owners, Text.compare, scopeKey(aliceConsumer), alice);\nMap.add(owners, Text.compare, scopeKey(bobConsumer), bob);\nMap.add(owners, Text.compare, scopeKey(bobSibling), bob);\nMap.add(owners, Text.compare, scopeKey(bobConsumerTwin), bob);\n'''
if anchor not in text:
    raise SystemExit("active scope setup anchor missing")
text = text.replace(anchor, addition, 1)

start = text.index('func owns(subject : Types.SubjectRef, value : Types.AppScopeRef) : Bool {')
end = text.index('func element(value : Types.AppScopeRef)', start)
replacement = '''func owns(subject : Types.SubjectRef, value : Types.AppScopeRef) : Bool {\n    let #principal(principal) = subject;\n    Map.get(owners, Text.compare, scopeKey(value)) == ?principal;\n};\n\nfunc subjectForScope(value : Types.AppScopeRef) : ?Types.SubjectRef {\n    switch (Map.get(owners, Text.compare, scopeKey(value))) {\n        case (?principal) ?#principal(principal);\n        case null null;\n    };\n};\n\n'''
text = text[:start] + replacement + text[end:]

old = '''func freshRandom() : async* Blob {\n    let seed = entropyCounter;\n    entropyCounter +%= 1;\n    Blob.fromArray(Array.tabulate<Nat8>(32, func(index) {\n        seed +% Nat8.fromNat(index);\n    }));\n};\n'''
new = '''func freshRandom() : async* Blob {\n    switch (freshRandomHook) {\n        case (?callback) {\n            freshRandomHook := null;\n            await* callback();\n        };\n        case null {};\n    };\n    let seed = entropyCounter;\n    entropyCounter +%= 1;\n    Blob.fromArray(Array.tabulate<Nat8>(32, func(index) {\n        seed +% Nat8.fromNat(index);\n    }));\n};\n'''
if old not in text:
    raise SystemExit("freshRandom target missing")
text = text.replace(old, new, 1)

anchor = '''// Restart creates a fresh service with no leases/providers while preserving\n// grant/revocation/redemption/epoch state and bearer-secret hashes.\n'''
security_tests = '''// The post-randomness recheck makes max_redemptions atomic across the await\n// boundary. The nested redemption consumes the only redemption while the outer\n// call is suspended; the outer call must then fail instead of overshooting 1.\nlet concurrentLimited = issueOk(await* aliceProviderAuthorization.issue({\n    resource = note;\n    audience = #principal(bob);\n    consumer_element = ?"plasmon";\n    rights = [#read];\n    expires_at = null;\n    max_redemptions = ?1;\n}));\nvar nestedRedemptionSucceeded = false;\nfunc consumeConcurrentLimit() : async* () {\n    switch (await* service.redeem({\n        token = concurrentLimited.token;\n        consumer_scope = bobConsumer;\n    }, bob)) {\n        case (#ok(_)) { nestedRedemptionSucceeded := true };\n        case (#err(_)) Runtime.trap("nested redemption should consume the limit");\n    };\n};\nfreshRandomHook := ?consumeConcurrentLimit;\nexpectRedeemDenied(await* service.redeem({\n    token = concurrentLimited.token;\n    consumer_scope = bobConsumer;\n}, bob));\nassert (nestedRedemptionSucceeded);\nlet ?concurrentStored = Map.get(\n    grants.grants,\n    Text.compare,\n    concurrentLimited.grant.grant_id,\n) else Runtime.trap("concurrent grant missing");\nassert (concurrentStored.grant.redemption_count == 1);\n\n'''
if anchor not in text:
    raise SystemExit("restart anchor missing")
text = text.replace(anchor, security_tests + anchor, 1)

end_anchor = '''assert (storedPersistent.secret_hash != Text.encodeUtf8(persistentGrant.token));\n'''
ownership_tests = end_anchor + '''\n// If a physical provider AppScope is administratively reassigned, grants from\n// the former subject fail closed immediately and are not exposed through the\n// new subject's bound list. The exact scope remains the same; authority changes.\nlet transferGrant = issueOk(await* aliceProviderAuthorization.issue(\n    rootInput(note, #principal(bob), [#read], ?"plasmon", null),\n));\nlet transferLease = redeemOk(await* restarted.redeem({\n    token = transferGrant.token;\n    consumer_scope = bobConsumer;\n}, bob));\nMap.add(owners, Text.compare, scopeKey(aliceProvider), bob);\nexpectRedeemDenied(await* restarted.redeem({\n    token = transferGrant.token;\n    consumer_scope = bobConsumer;\n}, bob));\nswitch (await* restarted.authorizationCapability(bobConsumer).call({\n    lease_id = transferLease.lease_id;\n    requested_right = #read;\n    operation = "read";\n    payload = Blob.fromArray([]);\n})) {\n    case (#denied) {};\n    case _ Runtime.trap("former-owner lease must fail after provider reassignment");\n};\nlet transferInspection = restarted.inspect({\n    grant_id = transferGrant.grant.grant_id;\n});\nlet ?safeTransferInspection = transferInspection else {\n    Runtime.trap("transfer grant inspection missing");\n};\nassert (safeTransferInspection.revoked);\nassert (not Array.any(\n    restarted.authorizationCapability(aliceProvider).list(),\n    func(grant) { grant.grant_id == transferGrant.grant.grant_id },\n));\nlet newOwnerGrant = issueOk(await* restarted.authorizationCapability(aliceProvider).issue(\n    rootInput(note, #principal(alice), [#read], ?"plasmon", null),\n));\nassert (newOwnerGrant.grant.issuer_subject == #principal(bob));\nassert (newOwnerGrant.grant.issuer_scope == aliceProvider);\nassert (newOwnerGrant.grant.provider_scope == aliceProvider);\n'''
if end_anchor not in text:
    raise SystemExit("test end anchor missing")
text = text.replace(end_anchor, ownership_tests, 1)

p.write_text(text)
