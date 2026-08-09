import Map "mo:core/Map";
import Principal "mo:core/Principal";

module {
    // Stable MTN tenant -> assigned physical app instance ids.
    //
    // Physical ids are the stored representation. Uniqueness for
    // (principal, logical app) is derived through memory/app_instances/v1;
    // do not add a second logical-installation record here.
    //
    // Typical tenants have only a handful of grants, so copying/scanning a
    // small [Text] remains preferable to a more complicated stable structure.
    // The root identity and this v1 layout are upgrade-sensitive once MTN
    // promises compatibility with deployed state.
    public type Mem = {
        grants : Map.Map<Principal, [Text]>;
    };

    public func init() : Mem {
        {
            grants = Map.empty<Principal, [Text]>();
        };
    };
};
