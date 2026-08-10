import Principal "mo:core/Principal";
import CapabilityTypes "../capabilities/Types";

module {
    // multitenancy-neutron 0.2 implements one subject kind while keeping the
    // representation tagged for future session/account subjects.
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

    // Public semantic grant. Raw bearer material and its stored hash are
    // intentionally absent.
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

    // Root issuance is AppScope-bound. The Kernel derives both issuer_scope and
    // provider_scope from the exact capability instance; callers cannot select
    // either scope in this input.
    public type IssueInput = {
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

    public type InspectInput = {
        grant_id : Text;
    };

    // Safe pre-authentication launch metadata. Exact resource identity and all
    // provider/issuer scope information are deliberately absent.
    public type GrantInspection = {
        namespace : Text;
        resource_type : Text;
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

    // Resource epoch rotation is AppScope-bound. The exact provider scope is
    // the capability's bound scope, never caller-selected data.
    public type RotateResourceInput = {
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

    // One compiler-delivered capability is bound to one exact AppScope. Both
    // provider-side management and consumer-side lease use inherit that scope;
    // no method accepts a caller-selectable issuer/provider/consumer scope.
    public type AuthorizationCapabilityV1 = {
        issue : IssueInput -> async* IssueResult;
        list : () -> [AuthorizationGrant];
        revoke : RevokeInput -> MutationResult;
        rotate_resource : RotateResourceInput -> MutationResult;
        register_provider : ProviderDispatch -> ();
        call : AuthorizedCallInput -> async* AuthorizedCallResult;
        delegate : DelegateInput -> async* IssueResult;
        release : ReleaseInput -> ();
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

    // Generic discovery: clients check operation names, never a product or
    // release string.
    public type CapabilityDiscovery = {
        operations : [Text];
        rights : [ResourceRight];
    };
};
