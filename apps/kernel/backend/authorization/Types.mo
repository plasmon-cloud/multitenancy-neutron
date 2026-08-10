import Principal "mo:core/Principal";
import CapabilityTypes "../capabilities/Types";

module {
    // MTN 0.2 deliberately implements one subject kind, but keeps the
    // representation tagged so future session/account subjects can be added
    // without redefining existing grants.
    public type SubjectRef = {
        #principal : Principal;
    };

    public type AppScopeRef = CapabilityTypes.AppScope;

    public type ResourceRef = {
        namespace : Text;
        resource_id : Text;
        resource_type : Text;
    };

    public type GrantAudience = {
        #any_authenticated;
        #principal : Principal;
    };

    public type ResourceRight = {
        #read;
        #write;
        #reshare;
    };

    // Public semantic grant. The stored secret hash is intentionally not part
    // of this type so list/inspect APIs cannot expose it accidentally.
    public type AuthorizationGrant = {
        grant_id : Text;
        issuer_subject : SubjectRef;
        issuer_scope : AppScopeRef;
        provider_scope : AppScopeRef;
        resource : ResourceRef;
        audience : GrantAudience;
        consumer_element : ?Text;
        rights : [ResourceRight];
        created_at : Nat64;
        expires_at : ?Nat64;
        revoked_at : ?Nat64;
        parent_grant_id : ?Text;
        resource_authorization_epoch : Nat64;
        max_redemptions : ?Nat;
        redemption_count : Nat;
    };

    // Stable record. Raw bearer material is never stored.
    public type StoredGrant = {
        grant : AuthorizationGrant;
        secret_hash : Blob;
    };

    public type AuthorizationLease = {
        lease_id : Text;
        grant_id : Text;
        subject : SubjectRef;
        consumer_scope : AppScopeRef;
        provider_scope : AppScopeRef;
        resource : ResourceRef;
        rights : [ResourceRight];
        issued_at : Nat64;
        expires_at : Nat64;
    };

    public type AuthorizationContext = {
        grant_id : Text;
        lease_id : Text;
        subject : SubjectRef;
        consumer_scope : AppScopeRef;
        provider_scope : AppScopeRef;
        resource : ResourceRef;
        rights : [ResourceRight];
    };

    // Root grants are issued by the provider itself. The issuer scope is
    // therefore the exact provider scope and is derived by the Kernel.
    public type IssueInput = {
        provider_scope : AppScopeRef;
        resource : ResourceRef;
        audience : GrantAudience;
        consumer_element : ?Text;
        rights : [ResourceRight];
        expires_at : ?Nat64;
        max_redemptions : ?Nat;
    };

    public type IssueOutput = {
        grant : AuthorizationGrant;
        // Returned exactly once. Raw bearer material is never persisted.
        token : Text;
    };

    public type ListInput = {
        issuer_scope : AppScopeRef;
    };

    public type InspectInput = {
        grant_id : Text;
    };

    public type GrantInspection = {
        grant_id : Text;
        resource : ResourceRef;
        consumer_element : ?Text;
        rights : [ResourceRight];
        expires_at : ?Nat64;
        revoked : Bool;
    };

    public type RedeemInput = {
        token : Text;
        consumer_scope : AppScopeRef;
    };

    public type ReleaseInput = {
        lease_id : Text;
    };

    public type RevokeInput = {
        grant_id : Text;
    };

    public type RotateResourceInput = {
        provider_scope : AppScopeRef;
        resource : ResourceRef;
    };

    // Delegation never accepts provider/resource from the caller. Those are
    // inherited from the validated parent lease by construction.
    public type DelegateInput = {
        lease_id : Text;
        audience : GrantAudience;
        consumer_element : ?Text;
        rights : [ResourceRight];
        expires_at : ?Nat64;
        max_redemptions : ?Nat;
    };

    public type AuthorizedCallInput = {
        lease_id : Text;
        requested_right : ResourceRight;
        operation : Text;
        payload : Blob;
    };

    public type AuthorizedCallRequest = {
        authorization : AuthorizationContext;
        operation : Text;
        payload : Blob;
    };

    public type AuthorizedCallResult = {
        #ok : Blob;
        #denied;
        #provider_unavailable;
    };

    public type ProviderDispatch = AuthorizedCallRequest -> async* Blob;

    // This capability is compiler-bound to the exact consumer AppScope. Apps
    // do not supply a caller scope or provider scope to call/delegate/release.
    public type AuthorizationCapabilityV1 = {
        call : AuthorizedCallInput -> async* AuthorizedCallResult;
        delegate : DelegateInput -> async* IssueResult;
        release : ReleaseInput -> ();
    };

    // Providers register only a callback; the compiler/kernel binds it to the
    // provider's own exact AppScope.
    public type AuthorizationProviderV1 = {
        register : ProviderDispatch -> ();
    };

    public type AuthorizationError = {
        #invalid_request;
        #unauthenticated;
        #not_authorized;
        #denied;
        #unavailable;
    };

    public type IssueResult = {
        #ok : IssueOutput;
        #err : AuthorizationError;
    };

    public type RedeemResult = {
        #ok : AuthorizationLease;
        #err : AuthorizationError;
    };

    public type MutationResult = {
        #ok;
        #err : AuthorizationError;
    };

    public type AuditEvent = {
        id : Nat64;
        at : Nat64;
        kind : Text;
        grant_id : ?Text;
        subject : ?SubjectRef;
        consumer_scope : ?AppScopeRef;
        provider_scope : ?AppScopeRef;
        resource : ?ResourceRef;
    };

    // Generic discovery: clients check for operation names, never a product or
    // release string.
    public type CapabilityDiscovery = {
        operations : [Text];
        rights : [ResourceRight];
    };
};
