import Map "mo:core/Map";
import AuthorizationTypes "../../authorization/Types";

module {
    // Stable multitenancy-neutron 0.2 authorization grants. Bearer
    // tokens/secrets are never members of this schema; only the
    // domain-separated secret hash is stored.
    public type Mem = {
        grants : Map.Map<Text, AuthorizationTypes.StoredGrant>;
    };

    public func init() : Mem {
        {
            grants = Map.empty<Text, AuthorizationTypes.StoredGrant>();
        };
    };
};
