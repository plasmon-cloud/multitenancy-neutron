#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/test/motoko/authorization_service_test.mo")
text = p.read_text()

if 'import Nat64 "mo:core/Nat64";' not in text:
    text = text.replace('import Nat8 "mo:core/Nat8";\n', 'import Nat8 "mo:core/Nat8";\nimport Nat64 "mo:core/Nat64";\n', 1)
text = text.replace('value.installation_uid.toText()', 'Nat64.toText(value.installation_uid)')
text = text.replace('func newService() : Service.Service {', 'func newService() {')

anchor = '''// Release removes only this ephemeral lease.\nconsumer.release({ lease_id = lease.lease_id });\n'''
addition = '''// A read/write grant permits write and still cannot delegate without reshare.\nlet readWriteGrant = issueOk(await* service.issue(\n    rootInput(note, #principal(bob), [#read, #write], ?"plasmon", null),\n    alice,\n));\nlet readWriteLease = redeemOk(await* service.redeem({\n    token = readWriteGrant.token;\n    consumer_scope = bobConsumer;\n}, bob));\nswitch (await* consumer.call({\n    lease_id = readWriteLease.lease_id;\n    requested_right = #write;\n    operation = "write";\n    payload = Blob.fromArray([]);\n})) {\n    case (#ok(_)) {};\n    case _ Runtime.trap("read/write lease must write");\n};\nexpectIssueDenied(await* consumer.delegate({\n    lease_id = readWriteLease.lease_id;\n    audience = #any_authenticated;\n    consumer_element = ?"plasmon";\n    rights = [#read];\n    expires_at = null;\n    max_redemptions = null;\n}));\n\n'''
if addition not in text:
    text = text.replace(anchor, addition + anchor, 1)

anchor2 = '''let child = issueOk(await* consumer.delegate({\n'''
expiry_test = '''let finiteParent = issueOk(await* service.issue(\n    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", ?(clock + 1_000)),\n    alice,\n));\nlet finiteLease = redeemOk(await* service.redeem({\n    token = finiteParent.token;\n    consumer_scope = bobConsumer;\n}, bob));\nexpectIssueDenied(await* consumer.delegate({\n    lease_id = finiteLease.lease_id;\n    audience = #any_authenticated;\n    consumer_element = ?"plasmon";\n    rights = [#read];\n    expires_at = ?(clock + 1_001);\n    max_redemptions = null;\n}));\n\n'''
if expiry_test not in text:
    text = text.replace(anchor2, expiry_test + anchor2, 1)

# One-redemption grants are enforced persistently.
anchor3 = '''// Restart creates a fresh service with no leases/providers but preserves grants,\n'''
limit_test = '''let limited = issueOk(await* service.issue({\n    provider_scope = aliceProvider;\n    resource = note;\n    audience = #principal(bob);\n    consumer_element = ?"plasmon";\n    rights = [#read];\n    expires_at = null;\n    max_redemptions = ?1;\n}, alice));\nignore redeemOk(await* service.redeem({ token = limited.token; consumer_scope = bobConsumer }, bob));\nexpectRedeemDenied(await* service.redeem({ token = limited.token; consumer_scope = bobConsumer }, bob));\n\n'''
if limit_test not in text:
    text = text.replace(anchor3, limit_test + anchor3, 1)

p.write_text(text)
