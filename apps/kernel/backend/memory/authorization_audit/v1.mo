import Map "mo:core/Map";
import AuthorizationTypes "../../authorization/Types";

module {
    // Audit metadata intentionally excludes raw bearer material and secret
    // hashes. This root is versioned independently from grants and epochs.
    public type Mem = {
        events : Map.Map<Nat64, AuthorizationTypes.AuditEvent>;
        var next_id : Nat64;
    };

    public func init() : Mem {
        {
            events = Map.empty<Nat64, AuthorizationTypes.AuditEvent>();
            var next_id = 1;
        };
    };
};
