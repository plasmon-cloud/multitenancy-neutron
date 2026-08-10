import Map "mo:core/Map";

module {
    // Stable audit schema. It deliberately contains no bearer token, secret
    // hash, resource payload, or provider storage path.
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

    public type Mem = {
        events : Map.Map<Nat64, AuditEvent>;
        var next_id : Nat64;
    };

    public func init() : Mem {
        {
            events = Map.empty<Nat64, AuditEvent>();
            var next_id = 1;
        };
    };
};
