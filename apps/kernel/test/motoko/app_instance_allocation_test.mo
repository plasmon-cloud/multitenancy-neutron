import Map "mo:core/Map";
import Text "mo:core/Text";
import Allocation "../../backend/app_instances/Allocation";

let instances = Map.empty<Text, Text>();
Map.add(instances, Text.compare, "hello_001", "hello");
Map.add(instances, Text.compare, "hello_002", "hello");
Map.add(instances, Text.compare, "demo_001", "demo");

let grants = ["hello_002", "demo_001", "hello_001", "unregistered_001"];

// Legacy duplicate grants resolve deterministically.
assert (
    Allocation.allocatedInstanceForApp(
        grants,
        instances,
        "hello",
        func(_appInstanceId : Text) : Bool { true },
    ) == ?"hello_001"
);

// Unusable/retired instances are ignored.
assert (
    Allocation.allocatedInstanceForApp(
        grants,
        instances,
        "hello",
        func(appInstanceId : Text) : Bool { appInstanceId != "hello_001" },
    ) == ?"hello_002"
);

assert (
    Allocation.allocatedInstanceForApp(
        grants,
        instances,
        "demo",
        func(_appInstanceId : Text) : Bool { true },
    ) == ?"demo_001"
);

assert (
    Allocation.allocatedInstanceForApp(
        grants,
        instances,
        "missing",
        func(_appInstanceId : Text) : Bool { true },
    ) == null
);

assert (
    Allocation.allocatedInstanceForApp(
        ["unregistered_001"],
        instances,
        "hello",
        func(_appInstanceId : Text) : Bool { true },
    ) == null
);
