import Map "mo:core/Map";

module {
    // Stable MTN logical-app catalog metadata.
    //
    // These keys are logical application ids, not physical Neutron app
    // instance ids. Keep this distinction intact: allocation maps logical ids
    // to tenant-specific physical execution scopes elsewhere. Because this is
    // a v1 stable-memory layout, changing key semantics or field structure
    // requires an explicit migration once upgrade compatibility is promised.
    public type AppMetadata = {
        name : Text;
        description : Text;
    };

    public type Mem = {
        apps : Map.Map<Text, AppMetadata>;
    };

    public func init() : Mem {
        {
            apps = Map.empty<Text, AppMetadata>();
        };
    };
};
