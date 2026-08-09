import Map "mo:core/Map";
import Text "mo:core/Text";

module {
    // Resolve the physical instance already assigned to one logical app.
    //
    // Tenant grants store physical app-instance ids. The logical relation is
    // derived through the app-instance registry rather than introducing a
    // second installation record.
    //
    // Older state may contain duplicate grants for one logical app. Reads are
    // deterministic in that case; allocation writes prevent new duplicates.
    public func allocatedInstanceForApp(
        grants : [Text],
        instances : Map.Map<Text, Text>,
        appId : Text,
        usable : (Text) -> Bool,
    ) : ?Text {
        var selected : ?Text = null;

        for (appInstanceId in grants.vals()) {
            switch (Map.get(instances, Text.compare, appInstanceId)) {
                case (?registeredAppId) {
                    if (registeredAppId == appId and usable(appInstanceId)) {
                        switch (selected) {
                            case null selected := ?appInstanceId;
                            case (?current) {
                                if (Text.compare(appInstanceId, current) == #less) {
                                    selected := ?appInstanceId;
                                };
                            };
                        };
                    };
                };
                case null {};
            };
        };

        selected;
    };
};
