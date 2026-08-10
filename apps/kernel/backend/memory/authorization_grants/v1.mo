import Map "mo:core/Map";

module {
    // Stable multitenancy-neutron 0.2 authorization-grant schema. Stable
    // schemas are deliberately self-contained: they do not import mutable
    // application modules, so their package hash is independently upgradeable.
    public type SubjectRef = {
        #principal : Principal;
    };

    public type AppScopeRef = {
        app_id : Text;
        installation_uid : Nat64;
    };

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

    // Raw bearer tokens/secrets are never members of this schema; only the
    // domain-separated one-way secret hash is persisted.
    public type StoredGrant = {
        grant : AuthorizationGrant;
        secret_hash : Blob;
    };

    public type Mem = {
        grants : Map.Map<Text, StoredGrant>;
    };

    public func init() : Mem {
        {
            grants = Map.empty<Text, StoredGrant>();
        };
    };
};
