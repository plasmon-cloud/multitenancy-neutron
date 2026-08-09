import Map "mo:core/Map";

module {
    // Stable multitenancy-neutron lifecycle state: physical app instance id ->
    // retired flag.
    //
    // Retirement is permanent non-reuse state, not a temporary capacity or
    // health signal. Allocation must never return a retired physical id.
    // Because this is a v1 stable-memory layout, changing the root identity,
    // key meaning, or value structure requires an explicit migration once
    // upgrade compatibility is promised.
    public type Mem = {
        retired : Map.Map<Text, Bool>;
    };

    public func init() : Mem {
        {
            retired = Map.empty<Text, Bool>();
        };
    };
};
