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

    public type IssueInput = {
        issuer_scope : AppScopeRef;
        provider_scope : AppScopeRef;
        resource : ResourceRef;
        audience : GrantAudience;
        consumer_element : ?Text;
        rights : [ResourceRight];
        expires_at : ?Nat64;
        parent_grant_id : ?Text;
        max_redemptions : ?Nat;
    };

    public type IssueOutput = {
        grant : AuthorizationGrant;
        // Returned exactly once. Neither value is persisted.
        secret : Text;
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
        grant_id : Text;
        secret : Text;
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

    public type AuthorizationCapabilityV1 = {
        call : AuthorizedCallInput -> async* AuthorizedCallResult;
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
