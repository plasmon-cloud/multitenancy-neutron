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

func scope(app : Text, uid : Nat64) : Types.AppScopeRef {
    { app_id = app; installation_uid = uid };
};

// Models an MTN 0.1 pool instance: physically installed/active before any
// tenant allocation has assigned the exact AppScope to a principal.
let poolProvider = scope("pool_notes_001", 101);
let siblingProvider = scope("pool_notes_002", 102);
let bobConsumer = scope("bob_plasmon_001", 201);
let aliceConsumer = scope("alice_plasmon_001", 202);

let poolNote : Types.ResourceRef = {
    namespace = "plasmon.atom";
    resource_id = "pool-note-1";
    resource_type = "notepad2/v1";
};
let siblingNote : Types.ResourceRef = {
    namespace = "plasmon.atom";
    resource_id = "pool-note-sibling";
    resource_type = "notepad2/v1";
};

let grants = GrantsMemory.init();
let epochs = EpochsMemory.init();
let audit = AuditMemory.init();
let active = Map.empty<Text, Bool>();
let owners = Map.empty<Text, Principal>();
var entropyCounter : Nat8 = 1;
let clock : Nat64 = 1_000_000_000_000;

func scopeKey(value : Types.AppScopeRef) : Text {
    value.app_id # ":" # Nat64.toText(value.installation_uid);
};

for (value in [
    poolProvider,
    siblingProvider,
    bobConsumer,
    aliceConsumer,
].vals()) {
    Map.add(active, Text.compare, scopeKey(value), true);
};

// Intentionally do NOT assign poolProvider here. The provider registers while
// this exact physical AppScope is active but still unallocated.
Map.add(owners, Text.compare, scopeKey(siblingProvider), alice);
Map.add(owners, Text.compare, scopeKey(bobConsumer), bob);
Map.add(owners, Text.compare, scopeKey(aliceConsumer), alice);

func isActive(value : Types.AppScopeRef) : Bool {
    Map.get(active, Text.compare, scopeKey(value)) == ?true;
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
    if (value == bobConsumer or value == aliceConsumer) ?"plasmon"
    else if (value == poolProvider or value == siblingProvider) ?"notepad2"
    else null;
};

func freshRandom() : async* Blob {
    let seed = entropyCounter;
    entropyCounter +%= 1;
    Blob.fromArray(Array.tabulate<Nat8>(32, func(index) {
        seed +% Nat8.fromNat(index);
    }));
};

let service = Service.Service(
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

func issueOk(result : Types.IssueResult) : Types.IssueOutput {
    switch (result) {
        case (#ok(value)) value;
        case (#err(_)) Runtime.trap("expected issue success");
    };
};

func redeemOk(result : Types.RedeemResult) : Types.AuthorizationLease {
    switch (result) {
        case (#ok(value)) value;
        case (#err(_)) Runtime.trap("expected redeem success");
    };
};

func expectIssueDenied(result : Types.IssueResult) : () {
    switch (result) {
        case (#err(_)) {};
        case (#ok(_)) Runtime.trap("unowned provider must not issue grants");
    };
};

func issueInput(
    resource : Types.ResourceRef,
    audience : Types.GrantAudience,
) : Types.IssueInput {
    {
        resource;
        audience;
        consumer_element = ?"plasmon";
        rights = [#read];
        expires_at = null;
        max_redemptions = null;
    };
};

let poolAuthorization = service.authorizationCapability(poolProvider);
let siblingAuthorization = service.authorizationCapability(siblingProvider);
let bobAuthorization = service.authorizationCapability(bobConsumer);
let aliceAuthorization = service.authorizationCapability(aliceConsumer);

assert (isActive(poolProvider));
assert (subjectForScope(poolProvider) == null);

var providerCalls : Nat = 0;
var expectedSubject : Types.SubjectRef = #principal(bob);
var expectedConsumer : Types.AppScopeRef = bobConsumer;

// Registration is exact-AppScope-bound compiler capability state. It must work
// while the preinstalled physical provider is active but still tenant-unowned.
poolAuthorization.register_provider(
    func(request : Types.AuthorizedCallRequest) : async* Blob {
        providerCalls += 1;
        assert (request.authorization.provider_scope == poolProvider);
        assert (request.authorization.resource == poolNote);
        assert (request.authorization.consumer_scope == expectedConsumer);
        assert (request.authorization.subject == expectedSubject);
        assert (request.authorization.rights == [#read]);
        Text.encodeUtf8("pool-provider-ok");
    },
);

// Registration did not manufacture grant authority. Until allocation assigns
// an owner, issue remains denied by the existing ownership boundary.
assert (subjectForScope(poolProvider) == null);
expectIssueDenied(await* poolAuthorization.issue(
    issueInput(poolNote, #principal(bob)),
));

// MTN 0.1 allocation happens after actor/app initialization.
Map.add(owners, Text.compare, scopeKey(poolProvider), alice);
assert (subjectForScope(poolProvider) == ?#principal(alice));

let allocatedGrant = issueOk(await* poolAuthorization.issue(
    issueInput(poolNote, #principal(bob)),
));
assert (allocatedGrant.grant.issuer_subject == #principal(alice));
assert (allocatedGrant.grant.provider_scope == poolProvider);
let allocatedLease = redeemOk(await* service.redeem({
    token = allocatedGrant.token;
    consumer_scope = bobConsumer;
}, bob));

switch (await* bobAuthorization.call({
    lease_id = allocatedLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#ok(body)) assert (Text.decodeUtf8(body) == ?"pool-provider-ok");
    case _ Runtime.trap("pre-allocation provider registration must survive allocation");
};
assert (providerCalls == 1);

// Exact-scope negative: a callback registered for provider A is not a routing
// callback for sibling physical provider B.
let siblingGrant = issueOk(await* siblingAuthorization.issue(
    issueInput(siblingNote, #principal(bob)),
));
let siblingLease = redeemOk(await* service.redeem({
    token = siblingGrant.token;
    consumer_scope = bobConsumer;
}, bob));
switch (await* bobAuthorization.call({
    lease_id = siblingLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#provider_unavailable) {};
    case _ Runtime.trap("provider A registration must not route provider B");
};
assert (providerCalls == 1);

// Provider dispatch belongs to the physical AppScope, not Alice. Reassignment
// invalidates Alice-issued authority, but the transient physical callback may
// remain. Bob can issue fresh authority from the same now-owned exact scope.
Map.add(owners, Text.compare, scopeKey(poolProvider), bob);
switch (await* bobAuthorization.call({
    lease_id = allocatedLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("former-owner lease must fail after provider reassignment");
};
assert (providerCalls == 1);

let reassignedGrant = issueOk(await* poolAuthorization.issue(
    issueInput(poolNote, #principal(alice)),
));
assert (reassignedGrant.grant.issuer_subject == #principal(bob));
assert (reassignedGrant.grant.provider_scope == poolProvider);
let reassignedLease = redeemOk(await* service.redeem({
    token = reassignedGrant.token;
    consumer_scope = aliceConsumer;
}, alice));

expectedSubject := #principal(alice);
expectedConsumer := aliceConsumer;
switch (await* aliceAuthorization.call({
    lease_id = reassignedLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#ok(body)) assert (Text.decodeUtf8(body) == ?"pool-provider-ok");
    case _ Runtime.trap("physical provider callback must survive tenant reassignment");
};
assert (providerCalls == 2);