import Map "mo:core/Map";

module {
    // Internal keys canonically encode exact provider AppScope + opaque
    // ResourceRef. Missing entries are authorization epoch zero.
    public type Mem = {
        epochs : Map.Map<Text, Nat64>;
    };

    public func init() : Mem {
        {
            epochs = Map.empty<Text, Nat64>();
        };
    };
};
