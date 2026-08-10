#!/usr/bin/env python3
from pathlib import Path

runner = Path("apps/kernel/test/motoko/run.ts")
text = runner.read_text()
needle = '  "authorization_service_test.mo",\n'
addition = needle + '  "authorization_upgrade_persistence_test.mo",\n'
if '"authorization_upgrade_persistence_test.mo"' not in text:
    if needle not in text:
        raise SystemExit("authorization_service_test.mo runner entry missing")
    text = text.replace(needle, addition, 1)
runner.write_text(text)

test = Path("apps/kernel/test/motoko/authorization_service_test.mo")
text = test.read_text()
old = '''        assert (request.authorization.resource == note);\n        assert (request.authorization.rights == [#read]);\n        Text.encodeUtf8("provider-ok");\n'''
new = '''        assert (request.authorization.resource == note);\n        if (request.operation == "read") {\n            assert (request.authorization.rights == [#read]);\n        } else if (request.operation == "write") {\n            assert (request.authorization.rights == [#read, #write]);\n        };\n        Text.encodeUtf8("provider-ok");\n'''
if old in text:
    text = text.replace(old, new, 1)

old = '''aliceOtherAuthorization.register_provider(\n    func(_request : Types.AuthorizedCallRequest) : async* Blob {\n        otherProviderCalls += 1;\n        Text.encodeUtf8("wrong-provider");\n    },\n);\n'''
new = '''aliceOtherAuthorization.register_provider(\n    func(request : Types.AuthorizedCallRequest) : async* Blob {\n        otherProviderCalls += 1;\n        assert (request.authorization.provider_scope == aliceOtherProvider);\n        assert (request.authorization.consumer_scope == bobConsumer);\n        assert (request.authorization.resource == otherNote);\n        Text.encodeUtf8("provider-b-ok");\n    },\n);\n'''
if old in text:
    text = text.replace(old, new, 1)

anchor = '''assert (providerCalls == 1);\nassert (otherProviderCalls == 0);\n'''
addition = anchor + '''\n// Provider B registration is independently bound to B; a fresh B grant routes\n// to B's callback without A being able to register or dispatch as B.\nlet providerBRouteGrant = issueOk(await* aliceOtherAuthorization.issue(\n    rootInput(otherNote, #principal(bob), [#read], ?"plasmon", null),\n));\nlet providerBRouteLease = redeemOk(await* service.redeem({\n    token = providerBRouteGrant.token;\n    consumer_scope = bobConsumer;\n}, bob));\nswitch (await* consumer.call({\n    lease_id = providerBRouteLease.lease_id;\n    requested_right = #read;\n    operation = "read";\n    payload = Blob.fromArray([]);\n})) {\n    case (#ok(body)) assert (Text.decodeUtf8(body) == ?"provider-b-ok");\n    case _ Runtime.trap("provider B lease must route only to provider B");\n};\nassert (providerCalls == 1);\nassert (otherProviderCalls == 1);\n'''
if 'let providerBRouteGrant' not in text:
    if anchor not in text:
        raise SystemExit("provider routing assertion anchor missing")
    text = text.replace(anchor, addition, 1)

test.write_text(text)
