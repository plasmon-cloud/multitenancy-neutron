import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Map "mo:core/Map";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import GrantsMemory "../../backend/memory/authorization_grants/v1";
import EpochsMemory "../../backend/memory/authorization_resource_epochs/v1";
import AuditMemory "../../backend/memory/authorization_audit/v1";
import Service "../../backend/authorization/Service";
import Types "../../backend/authorization/Types";

let alice = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let bob = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let anonymous = Principal.fromText("2vxsx-fae");

func scope(app : Text, uid : Nat64) : Types.AppScopeRef {
    { app_id = app; installation_uid = uid };
};

let aliceProvider = scope("alice_notes_001", 11);
let aliceOtherProvider = scope("alice_other_001", 12);
let bobConsumer = scope("bob_plasmon_001", 21);
let bobSibling = scope("bob_other_001", 22);
let aliceConsumer = scope("alice_plasmon_001", 31);

let note : Types.ResourceRef = {
    namespace = "plasmon.atom";
    resource_id = "atom-note-1";
    resource_type = "notepad2/v1";
};
let otherNote : Types.ResourceRef = {
    namespace = "plasmon.atom";
    resource_id = "atom-note-2";
    resource_type = "notepad2/v1";
};

let grants = GrantsMemory.init();
let epochs = EpochsMemory.init();
let audit = AuditMemory.init();
var clock : Nat64 = 1_000_000_000_000;
var entropyCounter : Nat8 = 1;
let active = Map.empty<Text, Bool>();

func scopeKey(value : Types.AppScopeRef) : Text {
    value.app_id # ":" # value.installation_uid.toText();
};
for (value in [aliceProvider, aliceOtherProvider, bobConsumer, bobSibling, aliceConsumer].vals()) {
    Map.add(active, Text.compare, scopeKey(value), true);
};

func isActive(value : Types.AppScopeRef) : Bool {
    switch (Map.get(active, Text.compare, scopeKey(value))) {
        case (?flag) flag;
        case null false;
    };
};

func owns(subject : Types.SubjectRef, value : Types.AppScopeRef) : Bool {
    let #principal(principal) = subject;
    if (principal == alice) {
        value == aliceProvider or value == aliceOtherProvider or value == aliceConsumer;
    } else if (principal == bob) {
        value == bobConsumer or value == bobSibling;
    } else false;
};

func element(value : Types.AppScopeRef) : ?Text {
    if (value == bobConsumer or value == aliceConsumer) ?"plasmon"
    else if (value == bobSibling) ?"other"
    else if (value == aliceProvider) ?"notepad2"
    else ?value.app_id;
};

func freshRandom() : async* Blob {
    let seed = entropyCounter;
    entropyCounter +%= 1;
    Blob.fromArray(Array.tabulate<Nat8>(32, func(index) {
        seed +% Nat8.fromNat(index);
    }));
};

func newService() : Service.Service {
    Service.Service(
        grants,
        epochs,
        audit,
        isActive,
        owns,
        element,
        freshRandom,
        func() { clock },
    );
};

func issueOk(result : Types.IssueResult) : Types.IssueOutput {
    switch (result) {
        case (#ok(value)) value;
        case (#err(_)) Runtime.trap("expected authorization issue success");
    };
};

func redeemOk(result : Types.RedeemResult) : Types.AuthorizationLease {
    switch (result) {
        case (#ok(value)) value;
        case (#err(_)) Runtime.trap("expected authorization redeem success");
    };
};

func expectIssueDenied(result : Types.IssueResult) : () {
    switch (result) {
        case (#err(_)) {};
        case (#ok(_)) Runtime.trap("expected authorization issue denial");
    };
};

func expectRedeemDenied(result : Types.RedeemResult) : () {
    switch (result) {
        case (#err(_)) {};
        case (#ok(_)) Runtime.trap("expected authorization redeem denial");
    };
};

func rootInput(
    resource : Types.ResourceRef,
    audience : Types.GrantAudience,
    rights : [Types.ResourceRight],
    consumerElement : ?Text,
    expiresAt : ?Nat64,
) : Types.IssueInput {
    {
        provider_scope = aliceProvider;
        resource;
        audience;
        consumer_element = consumerElement;
        rights;
        expires_at = expiresAt;
        max_redemptions = null;
    };
};

let service = newService();
let discovery = service.discovery();
assert (Array.any(discovery.operations, func(value) { value == "authorization.redeem" }));
assert (discovery.rights == [#read, #write, #reshare]);

// any_authenticated is authenticated-only; anonymous redemption always fails.
let anyGrant = issueOk(await* service.issue(
    rootInput(note, #any_authenticated, [#read], ?"plasmon", null),
    alice,
));
expectRedeemDenied(await* service.redeem({
    token = anyGrant.token;
    consumer_scope = bobConsumer;
}, anonymous));

// Invalid secret, wrong principal, wrong consumer Element, and scope ownership.
let readGrant = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
    alice,
));
let invalidToken = "mtn2_" # readGrant.grant.grant_id # "_" #
    "0000000000000000000000000000000000000000000000000000000000000000";
expectRedeemDenied(await* service.redeem({ token = invalidToken; consumer_scope = bobConsumer }, bob));
expectRedeemDenied(await* service.redeem({ token = readGrant.token; consumer_scope = aliceConsumer }, alice));
expectRedeemDenied(await* service.redeem({ token = readGrant.token; consumer_scope = bobSibling }, bob));
expectRedeemDenied(await* service.redeem({ token = readGrant.token; consumer_scope = aliceProvider }, bob));

// Safe inspection does not require authentication and exposes only safe launch metadata.
let inspected = service.inspect({ grant_id = readGrant.grant.grant_id });
let ?inspection = inspected else Runtime.trap("expected safe inspection");
assert (inspection.resource == note);
assert (inspection.consumer_element == ?"plasmon");
assert (inspection.rights == [#read]);

// List returns semantic grants only; bearer material/hash are not part of its type.
let listed = service.list({ issuer_scope = aliceProvider }, alice);
assert (Array.any(listed, func(grant) { grant.grant_id == readGrant.grant.grant_id }));
assert (service.list({ issuer_scope = aliceProvider }, bob).size() == 0);

let lease = redeemOk(await* service.redeem({
    token = readGrant.token;
    consumer_scope = bobConsumer;
}, bob));
let consumer = service.consumerCapability(bobConsumer);
let sibling = service.consumerCapability(bobSibling);
let provider = service.consumerCapability(aliceProvider);
let otherProvider = service.consumerCapability(aliceOtherProvider);
var providerCalls : Nat = 0;
var otherProviderCalls : Nat = 0;
provider.register_provider(func(request : Types.AuthorizedCallRequest) : async* Blob {
    providerCalls += 1;
    assert (request.authorization.provider_scope == aliceProvider);
    assert (request.authorization.consumer_scope == bobConsumer);
    assert (request.authorization.resource == note);
    assert (request.authorization.rights == [#read]);
    Text.encodeUtf8("provider-ok");
});
otherProvider.register_provider(func(_request : Types.AuthorizedCallRequest) : async* Blob {
    otherProviderCalls += 1;
    Text.encodeUtf8("wrong-provider");
});

// No grant/lease -> denied. Valid read reaches only the encoded provider.
switch (await* consumer.call({
    lease_id = "not-a-lease";
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("missing lease must be denied");
};
switch (await* consumer.call({
    lease_id = lease.lease_id;
    requested_right = #read;
    operation = "read";
    // Caller-controlled bytes deliberately claim a different resource/provider.
    // The provider asserts trusted context remains note/aliceProvider above.
    payload = Text.encodeUtf8("{\"resource_id\":\"atom-note-2\",\"provider\":\"alice_other_001\",\"rights\":[\"write\"]}");
})) {
    case (#ok(body)) assert (Text.decodeUtf8(body) == ?"provider-ok");
    case _ Runtime.trap("valid read lease must route");
};
assert (providerCalls == 1);
assert (otherProviderCalls == 0);

// Read-only cannot write and the same lease is non-transferable to Bob's sibling AppScope.
switch (await* consumer.call({
    lease_id = lease.lease_id;
    requested_right = #write;
    operation = "write";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("read-only lease must not write");
};
switch (await* sibling.call({
    lease_id = lease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("lease must not transfer to sibling AppScope");
};

// Release removes only this ephemeral lease.
consumer.release({ lease_id = lease.lease_id });
switch (await* consumer.call({
    lease_id = lease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("released lease must fail");
};

// Expiry and revocation are checked both at redemption and on cached leases.
let expiring = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", ?(clock + 100)),
    alice,
));
clock += 101;
expectRedeemDenied(await* service.redeem({ token = expiring.token; consumer_scope = bobConsumer }, bob));

let revocable = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
    alice,
));
let revocableLease = redeemOk(await* service.redeem({ token = revocable.token; consumer_scope = bobConsumer }, bob));
assert (service.revoke({ grant_id = revocable.grant.grant_id }, alice) == #ok);
switch (await* consumer.call({
    lease_id = revocableLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("revocation must invalidate cached lease");
};
expectRedeemDenied(await* service.redeem({ token = revocable.token; consumer_scope = bobConsumer }, bob));

// Resource epoch rotation invalidates all prior grants/leases for exactly this resource.
let rotatable = issueOk(await* service.issue(
    rootInput(otherNote, #principal(bob), [#read], ?"plasmon", null),
    alice,
));
let rotatedLease = redeemOk(await* service.redeem({ token = rotatable.token; consumer_scope = bobConsumer }, bob));
assert (service.rotateResource({ provider_scope = aliceProvider; resource = otherNote }, alice) == #ok);
expectRedeemDenied(await* service.redeem({ token = rotatable.token; consumer_scope = bobConsumer }, bob));
switch (await* consumer.call({
    lease_id = rotatedLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("rotated epoch must invalidate cached lease");
};

// Retired/inactive consumer and provider scopes fail closed.
let activeGrant = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
    alice,
));
Map.add(active, Text.compare, scopeKey(bobConsumer), false);
expectRedeemDenied(await* service.redeem({ token = activeGrant.token; consumer_scope = bobConsumer }, bob));
Map.add(active, Text.compare, scopeKey(bobConsumer), true);
Map.add(active, Text.compare, scopeKey(aliceProvider), false);
expectRedeemDenied(await* service.redeem({ token = activeGrant.token; consumer_scope = bobConsumer }, bob));
Map.add(active, Text.compare, scopeKey(aliceProvider), true);

// Delegation is lease-based: no reshare -> denied; child rights cannot increase.
let noReshareLease = redeemOk(await* service.redeem({ token = activeGrant.token; consumer_scope = bobConsumer }, bob));
expectIssueDenied(await* consumer.delegate({
    lease_id = noReshareLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));

let reshareRoot = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", null),
    alice,
));
let reshareLease = redeemOk(await* service.redeem({ token = reshareRoot.token; consumer_scope = bobConsumer }, bob));
expectIssueDenied(await* consumer.delegate({
    lease_id = reshareLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#write];
    expires_at = null;
    max_redemptions = null;
}));
let child = issueOk(await* consumer.delegate({
    lease_id = reshareLease.lease_id;
    audience = #principal(alice);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));
assert (child.grant.provider_scope == aliceProvider);
assert (child.grant.resource == note);
assert (child.grant.parent_grant_id == ?reshareRoot.grant.grant_id);
let childLease = redeemOk(await* service.redeem({ token = child.token; consumer_scope = aliceConsumer }, alice));
assert (service.revoke({ grant_id = reshareRoot.grant.grant_id }, alice) == #ok);
switch (await* service.consumerCapability(aliceConsumer).call({
    lease_id = childLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("parent revocation must invalidate child lease");
};

// Restart creates a fresh service with no leases/providers but preserves grants,
// revocations, redemption counts, resource epochs, and bearer-secret hashes.
let persistent = issueOk(await* service.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
    alice,
));
let beforeRestart = redeemOk(await* service.redeem({ token = persistent.token; consumer_scope = bobConsumer }, bob));
let restarted = newService();
assert (restarted.leaseCountForTesting() == 0);
switch (await* restarted.consumerCapability(bobConsumer).call({
    lease_id = beforeRestart.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("old lease must die on restart");
};
ignore redeemOk(await* restarted.redeem({ token = persistent.token; consumer_scope = bobConsumer }, bob));
expectRedeemDenied(await* restarted.redeem({ token = revocable.token; consumer_scope = bobConsumer }, bob));
assert (restarted.resourceEpochForTesting(aliceProvider, otherNote) == 1);

// Stable state contains a hash only, never the full bearer token/raw secret.
let ?storedPersistent = Map.get(grants.grants, Text.compare, persistent.grant.grant_id) else {
    Runtime.trap("expected persistent grant");
};
assert (storedPersistent.secret_hash.size() == 32);
assert (storedPersistent.secret_hash != Text.encodeUtf8(persistent.token));

// Root issuance cannot substitute a provider scope the caller does not own.
expectIssueDenied(await* service.issue({
    provider_scope = bobConsumer;
    resource = note;
    audience = #principal(bob);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}, alice));
