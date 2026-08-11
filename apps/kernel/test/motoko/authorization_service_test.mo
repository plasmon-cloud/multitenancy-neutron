import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Map "mo:core/Map";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
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

// Alice deliberately owns two provider sibling AppScopes. Provider-management
// tests below prove the bound capability for one cannot act as the other.
let aliceProvider = scope("alice_notes_001", 11);
let aliceOtherProvider = scope("alice_other_001", 12);
let bobConsumer = scope("bob_plasmon_001", 21);
let bobSibling = scope("bob_other_001", 22);
let bobConsumerTwin = scope("bob_plasmon_002", 23);
let aliceConsumer = scope("alice_plasmon_001", 31);
let unregisteredScope = scope("unregistered_physical_001", 41);

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
let rotatedNote : Types.ResourceRef = {
    namespace = "plasmon.atom";
    resource_id = "atom-note-3";
    resource_type = "notepad2/v1";
};

let grants = GrantsMemory.init();
let epochs = EpochsMemory.init();
let audit = AuditMemory.init();
var clock : Nat64 = 1_000_000_000_000;
var entropyCounter : Nat8 = 1;
var freshRandomHook : ?(() -> async* ()) = null;
let active = Map.empty<Text, Bool>();
let owners = Map.empty<Text, Principal>();

func scopeKey(value : Types.AppScopeRef) : Text {
    value.app_id # ":" # Nat64.toText(value.installation_uid);
};
for (value in [
    aliceProvider,
    aliceOtherProvider,
    bobConsumer,
    bobSibling,
    bobConsumerTwin,
    aliceConsumer,
    unregisteredScope,
].vals()) {
    Map.add(active, Text.compare, scopeKey(value), true);
};
Map.add(owners, Text.compare, scopeKey(aliceProvider), alice);
Map.add(owners, Text.compare, scopeKey(aliceOtherProvider), alice);
Map.add(owners, Text.compare, scopeKey(aliceConsumer), alice);
Map.add(owners, Text.compare, scopeKey(bobConsumer), bob);
Map.add(owners, Text.compare, scopeKey(bobSibling), bob);
Map.add(owners, Text.compare, scopeKey(bobConsumerTwin), bob);
Map.add(owners, Text.compare, scopeKey(unregisteredScope), bob);

func isActive(value : Types.AppScopeRef) : Bool {
    switch (Map.get(active, Text.compare, scopeKey(value))) {
        case (?flag) flag;
        case null false;
    };
};

func owns(subject : Types.SubjectRef, value : Types.AppScopeRef) : Bool {
    let #principal(principal) = subject;
    Map.get(owners, Text.compare, scopeKey(value)) == ?principal;
};

func subjectForScope(value : Types.AppScopeRef) : ?Types.SubjectRef {
    switch (Map.get(owners, Text.compare, scopeKey(value))) {
        case (?principal) ?#principal(principal);
        case null null;
    };
};

func element(value : Types.AppScopeRef) : ?Text {
    if (
        value == bobConsumer or
        value == bobConsumerTwin or
        value == aliceConsumer
    ) ?"plasmon"
    else if (value == bobSibling) ?"other"
    else if (value == aliceProvider) ?"notepad2"
    else if (value == aliceOtherProvider) ?"other_provider"
    else null;
};

func freshRandom() : async* Blob {
    switch (freshRandomHook) {
        case (?callback) {
            freshRandomHook := null;
            await* callback();
        };
        case null {};
    };
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
        subjectForScope,
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
        resource;
        audience;
        consumer_element = consumerElement;
        rights;
        expires_at = expiresAt;
        max_redemptions = null;
    };
};

let service = newService();
let aliceProviderAuthorization = service.authorizationCapability(aliceProvider);
let aliceOtherAuthorization = service.authorizationCapability(aliceOtherProvider);
let consumer = service.authorizationCapability(bobConsumer);
let sibling = service.authorizationCapability(bobSibling);
let consumerTwin = service.authorizationCapability(bobConsumerTwin);
let aliceConsumerAuthorization = service.authorizationCapability(aliceConsumer);

let discovery = service.discovery();
assert (Array.any(discovery.operations, func(value) { value == "authorization.issue" }));
assert (Array.any(discovery.operations, func(value) { value == "authorization.redeem" }));
assert (Array.any(discovery.operations, func(value) { value == "authorization.call" }));
assert (discovery.rights == [#read, #write, #reshare]);

// Provider/issuer management is bound to one exact AppScope. No management
// input contains provider_scope or issuer_scope, so sibling substitution is
// impossible by construction.
let providerBGrant = issueOk(await* aliceOtherAuthorization.issue(
    rootInput(otherNote, #principal(bob), [#read], ?"plasmon", null),
));
assert (providerBGrant.grant.provider_scope == aliceOtherProvider);
assert (providerBGrant.grant.issuer_scope == aliceOtherProvider);

let providerAAttempt = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(otherNote, #principal(bob), [#read], ?"plasmon", null),
));
assert (providerAAttempt.grant.provider_scope == aliceProvider);
assert (providerAAttempt.grant.provider_scope != aliceOtherProvider);

assert (Array.any(
    aliceOtherAuthorization.list(),
    func(grant) { grant.grant_id == providerBGrant.grant.grant_id },
));
assert (not Array.any(
    aliceProviderAuthorization.list(),
    func(grant) { grant.grant_id == providerBGrant.grant.grant_id },
));
assert (
    aliceProviderAuthorization.revoke({
        grant_id = providerBGrant.grant.grant_id;
    }) == #err(#not_authorized)
);

let bEpochBefore = service.resourceEpochForTesting(aliceOtherProvider, otherNote);
assert (aliceProviderAuthorization.rotate_resource({ resource = otherNote }) == #ok);
assert (
    service.resourceEpochForTesting(aliceOtherProvider, otherNote) == bEpochBefore
);
assert (aliceOtherAuthorization.rotate_resource({ resource = otherNote }) == #ok);
assert (
    service.resourceEpochForTesting(aliceOtherProvider, otherNote) ==
    bEpochBefore + 1
);

let providerBValid = issueOk(await* aliceOtherAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
));
assert (Array.any(
    aliceOtherAuthorization.list(),
    func(grant) { grant.grant_id == providerBValid.grant.grant_id },
));
assert (
    aliceOtherAuthorization.revoke({ grant_id = providerBValid.grant.grant_id }) ==
    #ok
);

// any_authenticated is authenticated-only; anonymous redemption always fails.
let anyGrant = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #any_authenticated, [#read], ?"plasmon", null),
));
expectRedeemDenied(await* service.redeem({
    token = anyGrant.token;
    consumer_scope = bobConsumer;
}, anonymous));

// Invalid secret, wrong principal, wrong Element, and wrong scope ownership.
let readGrant = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
));
let invalidToken = "mtn2_" # readGrant.grant.grant_id # "_" #
    "0000000000000000000000000000000000000000000000000000000000000000";
expectRedeemDenied(await* service.redeem({
    token = invalidToken;
    consumer_scope = bobConsumer;
}, bob));
expectRedeemDenied(await* service.redeem({
    token = readGrant.token;
    consumer_scope = aliceConsumer;
}, alice));
expectRedeemDenied(await* service.redeem({
    token = readGrant.token;
    consumer_scope = bobSibling;
}, bob));
expectRedeemDenied(await* service.redeem({
    token = readGrant.token;
    consumer_scope = aliceProvider;
}, bob));
// An active/owned physical scope without a registered Element does not fall
// back to app_id and therefore cannot satisfy an Element-restricted grant.
expectRedeemDenied(await* service.redeem({
    token = readGrant.token;
    consumer_scope = unregisteredScope;
}, bob));

// Safe inspection is usable before authentication but does not reveal the
// exact resource id or either AppScope because those fields do not exist in
// GrantInspection.
let inspected = service.inspect({ grant_id = readGrant.grant.grant_id });
let ?inspection = inspected else Runtime.trap("expected safe inspection");
assert (inspection.namespace == note.namespace);
assert (inspection.resource_type == note.resource_type);
assert (inspection.consumer_element == ?"plasmon");
assert (inspection.rights == [#read]);
assert (inspection.expires_at == null);
assert (not inspection.revoked);

let lease = redeemOk(await* service.redeem({
    token = readGrant.token;
    consumer_scope = bobConsumer;
}, bob));
var providerCalls : Nat = 0;
var otherProviderCalls : Nat = 0;
var expectedProviderRights : [Types.ResourceRight] = [#read];
aliceProviderAuthorization.register_provider(
    func(request : Types.AuthorizedCallRequest) : async* Blob {
        providerCalls += 1;
        assert (request.authorization.provider_scope == aliceProvider);
        assert (request.authorization.consumer_scope == bobConsumer);
        assert (request.authorization.resource == note);
        assert (request.authorization.rights == expectedProviderRights);
        Text.encodeUtf8("provider-ok");
    },
);
aliceOtherAuthorization.register_provider(
    func(_request : Types.AuthorizedCallRequest) : async* Blob {
        otherProviderCalls += 1;
        Text.encodeUtf8("wrong-provider");
    },
);

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
    payload = Text.encodeUtf8(
        "{\"resource_id\":\"atom-note-2\",\"provider\":\"alice_other_001\",\"rights\":[\"write\"]}",
    );
})) {
    case (#ok(body)) assert (Text.decodeUtf8(body) == ?"provider-ok");
    case _ Runtime.trap("valid read lease must route");
};
assert (providerCalls == 1);
assert (otherProviderCalls == 0);

// Read-only cannot write and the lease is non-transferable to either another
// Element or another AppScope of the same synthetic Element.
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
switch (await* consumerTwin.call({
    lease_id = lease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("lease must not transfer to another same-Element AppScope");
};

// A read/write grant permits write but cannot delegate without reshare.
let readWriteGrant = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read, #write], ?"plasmon", null),
));
let readWriteLease = redeemOk(await* service.redeem({
    token = readWriteGrant.token;
    consumer_scope = bobConsumer;
}, bob));
expectedProviderRights := [#read, #write];
switch (await* consumer.call({
    lease_id = readWriteLease.lease_id;
    requested_right = #write;
    operation = "write";
    payload = Blob.fromArray([]);
})) {
    case (#ok(_)) {};
    case _ Runtime.trap("read/write lease must write");
};
expectedProviderRights := [#read];
expectIssueDenied(await* consumer.delegate({
    lease_id = readWriteLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));

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
let expiring = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", ?(clock + 100)),
));
clock += 101;
expectRedeemDenied(await* service.redeem({
    token = expiring.token;
    consumer_scope = bobConsumer;
}, bob));

let revocable = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
));
let revocableLease = redeemOk(await* service.redeem({
    token = revocable.token;
    consumer_scope = bobConsumer;
}, bob));
assert (
    aliceProviderAuthorization.revoke({ grant_id = revocable.grant.grant_id }) ==
    #ok
);
switch (await* consumer.call({
    lease_id = revocableLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("revocation must invalidate cached lease");
};
expectRedeemDenied(await* service.redeem({
    token = revocable.token;
    consumer_scope = bobConsumer;
}, bob));

// Resource epoch rotation invalidates all prior grants/leases for exactly this
// provider/resource pair.
let rotatable = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(rotatedNote, #principal(bob), [#read], ?"plasmon", null),
));
let rotatedLease = redeemOk(await* service.redeem({
    token = rotatable.token;
    consumer_scope = bobConsumer;
}, bob));
assert (
    aliceProviderAuthorization.rotate_resource({ resource = rotatedNote }) == #ok
);
expectRedeemDenied(await* service.redeem({
    token = rotatable.token;
    consumer_scope = bobConsumer;
}, bob));
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
let activeGrant = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
));
Map.add(active, Text.compare, scopeKey(bobConsumer), false);
expectRedeemDenied(await* service.redeem({
    token = activeGrant.token;
    consumer_scope = bobConsumer;
}, bob));
Map.add(active, Text.compare, scopeKey(bobConsumer), true);
Map.add(active, Text.compare, scopeKey(aliceProvider), false);
expectRedeemDenied(await* service.redeem({
    token = activeGrant.token;
    consumer_scope = bobConsumer;
}, bob));
let ?inactiveInspection = service.inspect({
    grant_id = activeGrant.grant.grant_id;
}) else Runtime.trap("inactive grant inspection missing");
assert (inactiveInspection.revoked);
Map.add(active, Text.compare, scopeKey(aliceProvider), true);

// Delegation is lease-based: no reshare -> denied; child rights and lifetime
// cannot exceed the parent.
let noReshareLease = redeemOk(await* service.redeem({
    token = activeGrant.token;
    consumer_scope = bobConsumer;
}, bob));
expectIssueDenied(await* consumer.delegate({
    lease_id = noReshareLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));

let reshareRoot = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", null),
));
let reshareLease = redeemOk(await* service.redeem({
    token = reshareRoot.token;
    consumer_scope = bobConsumer;
}, bob));
expectIssueDenied(await* consumer.delegate({
    lease_id = reshareLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#write];
    expires_at = null;
    max_redemptions = null;
}));

let finiteParent = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(
        note,
        #principal(bob),
        [#read, #reshare],
        ?"plasmon",
        ?(clock + 1_000),
    ),
));
let finiteLease = redeemOk(await* service.redeem({
    token = finiteParent.token;
    consumer_scope = bobConsumer;
}, bob));
expectIssueDenied(await* consumer.delegate({
    lease_id = finiteLease.lease_id;
    audience = #any_authenticated;
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = ?(clock + 1_001);
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
let childLease = redeemOk(await* service.redeem({
    token = child.token;
    consumer_scope = aliceConsumer;
}, alice));
assert (
    aliceProviderAuthorization.revoke({ grant_id = reshareRoot.grant.grant_id }) ==
    #ok
);
switch (await* aliceConsumerAuthorization.call({
    lease_id = childLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("parent revocation must invalidate child lease");
};
let ?revokedChildInspection = service.inspect({
    grant_id = child.grant.grant_id;
}) else Runtime.trap("child inspection missing");
assert (revokedChildInspection.revoked);

// A delegated grant also fails if its own issuer AppScope becomes inactive.
let issuerRoot = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", null),
));
let issuerRootLease = redeemOk(await* service.redeem({
    token = issuerRoot.token;
    consumer_scope = bobConsumer;
}, bob));
let issuerChild = issueOk(await* consumer.delegate({
    lease_id = issuerRootLease.lease_id;
    audience = #principal(alice);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));
Map.add(active, Text.compare, scopeKey(bobConsumer), false);
expectRedeemDenied(await* service.redeem({
    token = issuerChild.token;
    consumer_scope = aliceConsumer;
}, alice));
let ?inactiveIssuerInspection = service.inspect({
    grant_id = issuerChild.grant.grant_id;
}) else Runtime.trap("inactive issuer inspection missing");
assert (inactiveIssuerInspection.revoked);
Map.add(active, Text.compare, scopeKey(bobConsumer), true);

// Delegation authority is revalidated after entropy awaits. Revoking the
// parent while child entropy is being acquired must prevent child persistence.
let awaitParent = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", null),
));
let awaitParentLease = redeemOk(await* service.redeem({
    token = awaitParent.token;
    consumer_scope = bobConsumer;
}, bob));
func revokeAwaitParent() : async* () {
    assert (
        aliceProviderAuthorization.revoke({
            grant_id = awaitParent.grant.grant_id;
        }) == #ok
    );
};
freshRandomHook := ?revokeAwaitParent;
expectIssueDenied(await* consumer.delegate({
    lease_id = awaitParentLease.lease_id;
    audience = #principal(alice);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));

// Root issuance also revalidates after entropy. Reassignment during entropy
// never persists stale Alice authority; the resulting grant records Bob, the
// unique owner at the final synchronous persistence point.
func reassignProviderDuringIssue() : async* () {
    Map.add(owners, Text.compare, scopeKey(aliceProvider), bob);
};
freshRandomHook := ?reassignProviderDuringIssue;
let reassignedDuringIssue = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(alice), [#read], ?"plasmon", null),
));
assert (reassignedDuringIssue.grant.issuer_subject == #principal(bob));
// Restore Alice for the tests that intentionally predate the final ownership
// reassignment acceptance case below.
Map.add(owners, Text.compare, scopeKey(aliceProvider), alice);

// Redemption limits are persistent grant state.
let limited = issueOk(await* aliceProviderAuthorization.issue({
    resource = note;
    audience = #principal(bob);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = ?1;
}));
ignore redeemOk(await* service.redeem({
    token = limited.token;
    consumer_scope = bobConsumer;
}, bob));
expectRedeemDenied(await* service.redeem({
    token = limited.token;
    consumer_scope = bobConsumer;
}, bob));

// The post-randomness reread makes max_redemptions atomic across the await
// boundary. A nested redemption consumes the only redemption while the outer
// call is suspended; the outer call must then fail and count must stay at 1.
let concurrentLimited = issueOk(await* aliceProviderAuthorization.issue({
    resource = note;
    audience = #principal(bob);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = ?1;
}));
var nestedRedemptionSucceeded = false;
func consumeConcurrentLimit() : async* () {
    switch (await* service.redeem({
        token = concurrentLimited.token;
        consumer_scope = bobConsumer;
    }, bob)) {
        case (#ok(_)) { nestedRedemptionSucceeded := true };
        case (#err(_)) Runtime.trap("nested redemption should consume the limit");
    };
};
freshRandomHook := ?consumeConcurrentLimit;
expectRedeemDenied(await* service.redeem({
    token = concurrentLimited.token;
    consumer_scope = bobConsumer;
}, bob));
assert (nestedRedemptionSucceeded);
let ?concurrentStored = Map.get(
    grants.grants,
    Text.compare,
    concurrentLimited.grant.grant_id,
) else Runtime.trap("concurrent grant missing");
assert (concurrentStored.grant.redemption_count == 1);

// Restart creates a fresh service with no leases/providers while preserving
// grant/revocation/redemption/epoch state and bearer-secret hashes.
let persistentGrant = issueOk(await* aliceProviderAuthorization.issue(
    rootInput(note, #principal(bob), [#read], ?"plasmon", null),
));
let beforeRestart = redeemOk(await* service.redeem({
    token = persistentGrant.token;
    consumer_scope = bobConsumer;
}, bob));
let restarted = newService();
assert (restarted.leaseCountForTesting() == 0);
switch (await* restarted.authorizationCapability(bobConsumer).call({
    lease_id = beforeRestart.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("old lease must die on restart");
};
ignore redeemOk(await* restarted.redeem({
    token = persistentGrant.token;
    consumer_scope = bobConsumer;
}, bob));
expectRedeemDenied(await* restarted.redeem({
    token = revocable.token;
    consumer_scope = bobConsumer;
}, bob));
assert (restarted.resourceEpochForTesting(aliceProvider, rotatedNote) == 1);
assert (Array.any(
    restarted.authorizationCapability(aliceProvider).list(),
    func(grant) { grant.grant_id == persistentGrant.grant.grant_id },
));

// Stable state contains a one-way hash only, never the full bearer token.
let ?storedPersistent = Map.get(
    grants.grants,
    Text.compare,
    persistentGrant.grant.grant_id,
) else Runtime.trap("expected persistent grant");
assert (storedPersistent.secret_hash.size() == 32);
assert (storedPersistent.secret_hash != Text.encodeUtf8(persistentGrant.token));

// If the exact physical provider AppScope is reassigned, former-subject grants
// fail immediately, cached leases fail, descendants fail through ancestry,
// inspection reports effective revocation, and the new subject sees none of
// the former subject's grants through bound list().
let transferRoot = issueOk(await* restarted.authorizationCapability(aliceProvider).issue(
    rootInput(note, #principal(bob), [#read, #reshare], ?"plasmon", null),
));
let transferRootLease = redeemOk(await* restarted.redeem({
    token = transferRoot.token;
    consumer_scope = bobConsumer;
}, bob));
let transferChild = issueOk(await* restarted.authorizationCapability(bobConsumer).delegate({
    lease_id = transferRootLease.lease_id;
    audience = #principal(alice);
    consumer_element = ?"plasmon";
    rights = [#read];
    expires_at = null;
    max_redemptions = null;
}));
let transferChildLease = redeemOk(await* restarted.redeem({
    token = transferChild.token;
    consumer_scope = aliceConsumer;
}, alice));

Map.add(owners, Text.compare, scopeKey(aliceProvider), bob);
expectRedeemDenied(await* restarted.redeem({
    token = transferRoot.token;
    consumer_scope = bobConsumer;
}, bob));
switch (await* restarted.authorizationCapability(bobConsumer).call({
    lease_id = transferRootLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("former-owner root lease must fail after reassignment");
};
switch (await* restarted.authorizationCapability(aliceConsumer).call({
    lease_id = transferChildLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("descendant lease must fail after provider reassignment");
};
let ?safeTransferInspection = restarted.inspect({
    grant_id = transferRoot.grant.grant_id;
}) else Runtime.trap("transfer grant inspection missing");
assert (safeTransferInspection.revoked);
let ?safeTransferChildInspection = restarted.inspect({
    grant_id = transferChild.grant.grant_id;
}) else Runtime.trap("transfer child inspection missing");
assert (safeTransferChildInspection.revoked);
assert (not Array.any(
    restarted.authorizationCapability(aliceProvider).list(),
    func(grant) { grant.grant_id == transferRoot.grant.grant_id },
));

let newOwnerGrant = issueOk(await* restarted.authorizationCapability(aliceProvider).issue(
    rootInput(note, #principal(alice), [#read], ?"plasmon", null),
));
assert (newOwnerGrant.grant.issuer_subject == #principal(bob));
assert (newOwnerGrant.grant.issuer_scope == aliceProvider);
assert (newOwnerGrant.grant.provider_scope == aliceProvider);
