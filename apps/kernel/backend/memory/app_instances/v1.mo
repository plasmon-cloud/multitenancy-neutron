import Map "mo:core/Map";

module {
    // Stable multitenancy-neutron physical Neutron app instance id -> logical
    // app id mapping.
    //
    // Example:
    //   hello_001 -> hello
    //   hello_002 -> hello
    //
    // Physical ids are persisted execution identities and logical ids are
    // persisted catalog identities. Renaming either side after deployment can
    // change the meaning of tenant grants and lifecycle state, so changes to
    // these semantics require an explicit migration once compatibility is
    // promised.
    public type Mem = {
        instances : Map.Map<Text, Text>;
    };

    public func init() : Mem {
        {
            instances = Map.empty<Text, Text>();
        };
    };
};
