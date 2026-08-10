import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Map "mo:core/Map";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import Allocation "../../backend/app_instances/Allocation";
import AppCatalogMemory "../../backend/memory/app_catalog/v1";
import AppInstancesMemory "../../backend/memory/app_instances/v1";
import LifecycleMemory "../../backend/memory/app_instance_lifecycle/v1";
import TenantsMemory "../../backend/memory/tenants/v1";
import GrantsMemory "../../backend/memory/authorization_grants/v1";
import EpochsMemory "../../backend/memory/authorization_resource_epochs/v1";
import AuditMemory "../../backend/memory/authorization_audit/v1";
import Service "../../backend/authorization/Service";
import Types "../../backend/authorization/Types";

let alice = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let bob = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

let tenants = TenantsMemory.init();
let instances = AppInstancesMemory.init();
let lifecycle = LifecycleMemory.init();
let catalog = AppCatalogMemory.init();

Map.add(instances.instances, Text.compare, "notes_001", "notes");
Map.add(instances.instances, Text.compare, "notes_099", "notes");
Map.add(instances.instances, Text.compare, "plasmon_001", "plasmon");
Map.add(tenants.grants, Principal.compare, alice, ["notes_001"]);
Map.add(tenants.grants, Principal.compare, bob, ["plasmon_001"]);
Map.add(lifecycle.retired, Text.compare, "notes_099", true);
Map.add(catalog.apps, Text.compare, "notes", {
    name = "Notes";
    description = "notes element";
});
Map.add(catalog.apps, Text.compare, "plasmon", {
    name = "Plasmon";
    description = "plasmon element";
});

let grants = GrantsMemory.init();
let epochs = EpochsMemory.init();
let audit = AuditMemory.init();
var clock : Nat64 = 5_000_000_000_000;
var entropyCounter : Nat8 = 1;

func scope(appId : Text, uid : Nat64) : Types.AppScopeRef {
    { app_id = appId; installation_uid = uid };
};
let aliceProvider = scope("notes_001", 11);
let bobConsumer = scope("plasmon_001", 21);

func retired(appId : Text) : Bool {
    switch (Map.get(lifecycle.retired, Text.compare, appId)) {
        case (?true) true;
        case _ false;
    };
};

func active(value : Types.AppScopeRef) : Bool {
    value.installation_uid > 0 and
    Map.get(instances.instances, Text.compare, value.app_id) != null and
    not retired(value.app_id);
};

func owns(subject : Types.SubjectRef, value : Types.AppScopeRef) : Bool {
    let #principal(principal) = subject;
    switch (Map.get(tenants.grants, Principal.compare, principal)) {
        case null false;
        case (?apps) Array.any(apps, func(appId : Text) : Bool {
            appId == value.app_id;
        });
    };
};

func subjectForScope(value : Types.AppScopeRef) : ?Types.SubjectRef {
    var found : ?Principal = null;
    for ((principal, apps) in Map.entries(tenants.grants)) {
        if (Array.any(apps, func(appId : Text) : Bool { appId == value.app_id })) {
            switch (found) {
                case null { found := ?principal };
                case (?existing) { if (existing != principal) return null };
            };
        };
    };
    switch (found) {
        case (?principal) ?#principal(principal);
        case null null;
    };
};

func element(value : Types.AppScopeRef) : ?Text {
    Map.get(instances.instances, Text.compare, value.app_id);
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
        active,
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
        case (#err(_)) Runtime.trap("expected issue success");
    };
};

func redeemOk(result : Types.RedeemResult) : Types.AuthorizationLease {
    switch (result) {
        case (#ok(value)) value;
        case (#err(_)) Runtime.trap("expected redeem success");
    };
};

func expectRedeemDenied(result : Types.RedeemResult) : () {
    switch (result) {
        case (#err(_)) {};
        case (#ok(_)) Runtime.trap("expected redeem denial");
    };
};

func input(resourceId : Text) : Types.IssueInput {
    {
        resource = {
            namespace = "test.resource";
            resource_id = resourceId;
            resource_type = "notes/v1";
        };
        audience = #principal(bob);
        consumer_element = ?"plasmon";
        rights = [#read];
        expires_at = null;
        max_redemptions = null;
    };
};

let beforeUpgrade = newService();
let provider = beforeUpgrade.authorizationCapability(aliceProvider);
let validGrant = issueOk(await* provider.issue(input("valid")));
let revokedGrant = issueOk(await* provider.issue(input("revoked")));
let rotatedGrant = issueOk(await* provider.issue(input("rotated")));
let oldLease = redeemOk(await* beforeUpgrade.redeem({
    token = validGrant.token;
    consumer_scope = bobConsumer;
}, bob));
assert (provider.revoke({ grant_id = revokedGrant.grant.grant_id }) == #ok);
assert (provider.rotate_resource({ resource = rotatedGrant.grant.resource }) == #ok);

// This is the 0.1 allocator state that must remain authoritative through the
// additive 0.2 authorization upgrade.
assert (Allocation.allocatedInstanceForApp(
    switch (Map.get(tenants.grants, Principal.compare, alice)) {
        case (?apps) apps;
        case null [];
    },
    instances.instances,
    "notes",
    func(appId : Text) : Bool { not retired(appId) },
) == ?"notes_001");
assert (Map.get(lifecycle.retired, Text.compare, "notes_099") == ?true);
assert (Map.get(instances.instances, Text.compare, "notes_001") == ?"notes");
assert (Map.get(instances.instances, Text.compare, "plasmon_001") == ?"plasmon");
let ?notesMetadata = Map.get(catalog.apps, Text.compare, "notes") else {
    Runtime.trap("notes catalog entry missing");
};
assert (notesMetadata.name == "Notes");

// Re-instantiation models the post-upgrade service over the same stable roots.
// Authorization leases/provider callbacks are intentionally transient.
let afterUpgrade = newService();
assert (afterUpgrade.leaseCountForTesting() == 0);
switch (await* afterUpgrade.authorizationCapability(bobConsumer).call({
    lease_id = oldLease.lease_id;
    requested_right = #read;
    operation = "read";
    payload = Blob.fromArray([]);
})) {
    case (#denied) {};
    case _ Runtime.trap("pre-upgrade lease must not survive");
};

// Existing 0.1 tenant/allocation/lifecycle/catalog state remains byte-for-byte
// meaningful and produces the same allocation decision.
assert (Allocation.allocatedInstanceForApp(
    switch (Map.get(tenants.grants, Principal.compare, alice)) {
        case (?apps) apps;
        case null [];
    },
    instances.instances,
    "notes",
    func(appId : Text) : Bool { not retired(appId) },
) == ?"notes_001");
assert (Map.get(lifecycle.retired, Text.compare, "notes_099") == ?true);
assert (Map.get(instances.instances, Text.compare, "notes_001") == ?"notes");
assert (Map.get(instances.instances, Text.compare, "plasmon_001") == ?"plasmon");
assert (Map.size(tenants.grants) == 2);
assert (Map.size(instances.instances) == 3);
assert (Map.size(catalog.apps) == 2);

// New authorization roots survive: usable grant remains redeemable, revoked
// remains revoked, resource epoch remains advanced.
ignore redeemOk(await* afterUpgrade.redeem({
    token = validGrant.token;
    consumer_scope = bobConsumer;
}, bob));
expectRedeemDenied(await* afterUpgrade.redeem({
    token = revokedGrant.token;
    consumer_scope = bobConsumer;
}, bob));
expectRedeemDenied(await* afterUpgrade.redeem({
    token = rotatedGrant.token;
    consumer_scope = bobConsumer;
}, bob));
assert (
    afterUpgrade.resourceEpochForTesting(
        aliceProvider,
        rotatedGrant.grant.resource,
    ) == 1
);

// Stable grant state contains only the hash, never the bearer token/secret.
let ?stored = Map.get(
    grants.grants,
    Text.compare,
    validGrant.grant.grant_id,
) else Runtime.trap("valid grant missing after upgrade");
assert (stored.secret_hash.size() == 32);
assert (stored.secret_hash != Text.encodeUtf8(validGrant.token));
