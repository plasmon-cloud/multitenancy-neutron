import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Map "mo:core/Map";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Sha256 "mo:sha2/Sha256";
import CapabilityScope "../capabilities/Scope";
import GrantsMemory "../memory/authorization_grants/v1";
import EpochsMemory "../memory/authorization_resource_epochs/v1";
import AuditMemory "../memory/authorization_audit/v1";
import Types "Types";

module {
    func isAnonymous(principal : Principal) : Bool {
        principal == Principal.fromText("2vxsx-fae");
    };

    let LEASE_LIFETIME_NS : Nat64 = 300_000_000_000;
    let MAX_ANCESTRY_DEPTH : Nat = 64;
    let TOKEN_PREFIX = "mtn2";
    let SECRET_HASH_DOMAIN = "multitenancy-neutron.authorization.secret.v1\00";
    let LOWER_HEX_DIGITS : [Text] = [
        "0", "1", "2", "3", "4", "5", "6", "7",
        "8", "9", "a", "b", "c", "d", "e", "f",
    ];

    public class Service(
        grantsMem : GrantsMemory.Mem,
        epochsMem : EpochsMemory.Mem,
        auditMem : AuditMemory.Mem,
        scopeActive : Types.AppScopeRef -> Bool,
        subjectOwnsScope : (Types.SubjectRef, Types.AppScopeRef) -> Bool,
        scopeSubject : Types.AppScopeRef -> ?Types.SubjectRef,
        scopeElement : Types.AppScopeRef -> ?Text,
        freshRandom : () -> async* Blob,
        now : () -> Nat64,
    ) {
        // Leases and provider callbacks are deliberately transient. Restart or
        // upgrade invalidates every old lease while persistent grants remain
        // redeemable according to their policy.
        let leases = Map.empty<Text, Types.AuthorizationLease>();
        let providerDispatch = Map.empty<Text, Types.ProviderDispatch>();

        public func discovery() : Types.CapabilityDiscovery {
            {
                operations = [
                    "authorization.issue",
                    "authorization.list",
                    "authorization.inspect",
                    "authorization.redeem",
                    "authorization.release",
                    "authorization.revoke",
                    "authorization.rotate_resource",
                    "authorization.delegate",
                    "authorization.call",
                ];
                rights = [#read, #write, #reshare];
            };
        };

        // Safe pre-authentication metadata inspection. Exact resource identity,
        // provider/issuer scope, bearer material, and storage paths are absent.
        // `revoked` represents effective non-expiry invalidation, including
        // issuer ownership/liveness, resource epochs, and invalid ancestry.
        public func inspect(input : Types.InspectInput) : ?Types.GrantInspection {
            let ?stored = Map.get(grantsMem.grants, Text.compare, input.grant_id) else {
                return null;
            };
            let grant = stored.grant;
            ?{
                namespace = grant.resource.namespace;
                resource_type = grant.resource.resource_type;
                consumer_element = grant.consumer_element;
                rights = grant.rights;
                expires_at = grant.expires_at;
                revoked = effectivelyRevoked(grant);
            };
        };

        // Redemption is the one subject-bound public operation accepting an
        // explicit consumer AppScope. Ownership and Element are revalidated.
        public func redeem(
            input : Types.RedeemInput,
            caller : Principal,
        ) : async* Types.RedeemResult {
            if (isAnonymous(caller)) return #err(#unauthenticated);

            let ?token = parseToken(input.token) else return #err(#denied);
            let ?stored = Map.get(
                grantsMem.grants,
                Text.compare,
                token.grant_id,
            ) else return #err(#denied);

            if (not secretMatches(
                token.grant_id,
                token.secret,
                stored.secret_hash,
            )) return #err(#denied);

            let subject : Types.SubjectRef = #principal(caller);
            let grant = stored.grant;

            if (
                not grantUsable(grant) or
                not audienceAllows(grant.audience, subject) or
                not CapabilityScope.valid(input.consumer_scope) or
                not scopeActive(input.consumer_scope) or
                not subjectOwnsScope(subject, input.consumer_scope) or
                not consumerElementAllows(
                    grant.consumer_element,
                    input.consumer_scope,
                ) or
                not redemptionAvailable(grant)
            ) return #err(#denied);

            let leaseRandom = await* freshRandom();
            if (leaseRandom.size() < 32) return #err(#unavailable);

            // freshRandom is an await boundary. Re-read and revalidate every
            // authority-bearing fact after it. No await occurs between this
            // final validation and the persistent redemption-count increment.
            let ?currentStored = Map.get(
                grantsMem.grants,
                Text.compare,
                token.grant_id,
            ) else return #err(#denied);

            if (not secretMatches(
                token.grant_id,
                token.secret,
                currentStored.secret_hash,
            )) return #err(#denied);

            let currentGrant = currentStored.grant;
            if (
                not grantUsable(currentGrant) or
                not audienceAllows(currentGrant.audience, subject) or
                not CapabilityScope.valid(input.consumer_scope) or
                not scopeActive(input.consumer_scope) or
                not subjectOwnsScope(subject, input.consumer_scope) or
                not consumerElementAllows(
                    currentGrant.consumer_element,
                    input.consumer_scope,
                ) or
                not redemptionAvailable(currentGrant)
            ) return #err(#denied);

            let leaseId = hex(leaseRandom);
            let issuedAt = now();
            let nominalLeaseExpiry = issuedAt + LEASE_LIFETIME_NS;
            let effectiveLeaseExpiry = switch (currentGrant.expires_at) {
                case (?grantExpiry) {
                    if (grantExpiry < nominalLeaseExpiry) grantExpiry
                    else nominalLeaseExpiry;
                };
                case null nominalLeaseExpiry;
            };

            let lease : Types.AuthorizationLease = {
                lease_id = leaseId;
                grant_id = currentGrant.grant_id;
                subject;
                consumer_scope = input.consumer_scope;
                provider_scope = currentGrant.provider_scope;
                resource = currentGrant.resource;
                rights = currentGrant.rights;
                issued_at = issuedAt;
                expires_at = effectiveLeaseExpiry;
            };

            let updatedGrant = copyGrantWithRedemptionCount(
                currentGrant,
                currentGrant.redemption_count + 1,
            );

            Map.add(
                grantsMem.grants,
                Text.compare,
                currentGrant.grant_id,
                {
                    grant = updatedGrant;
                    secret_hash = currentStored.secret_hash;
                },
            );

            Map.add(leases, Text.compare, leaseId, lease);

            appendAudit(
                "redeem",
                ?currentGrant.grant_id,
                ?subject,
                ?input.consumer_scope,
                ?currentGrant.provider_scope,
                ?currentGrant.resource,
            );

            #ok(lease);
        };

        // One compiler-delivered capability is permanently bound to one exact
        // AppScope. None of these methods accepts a sibling scope selector.
        public func authorizationCapability(
            boundScope : Types.AppScopeRef,
        ) : Types.AuthorizationCapabilityV1 {
            {
                issue = func(
                    input : Types.IssueInput
                ) : async* Types.IssueResult {
                    await* issueFromScope(boundScope, input);
                };

                list = func() : [Types.AuthorizationGrant] {
                    listFromScope(boundScope);
                };

                revoke = func(
                    input : Types.RevokeInput
                ) : Types.MutationResult {
                    revokeFromScope(boundScope, input);
                };

                rotate_resource = func(
                    input : Types.RotateResourceInput
                ) : Types.MutationResult {
                    rotateResourceFromScope(boundScope, input);
                };

                register_provider = func(
                    dispatch : Types.ProviderDispatch
                ) : () {
                    registerProviderFromScope(boundScope, dispatch);
                };

                call = func(
                    input : Types.AuthorizedCallInput
                ) : async* Types.AuthorizedCallResult {
                    await* callFromScope(boundScope, input);
                };

                delegate = func(
                    input : Types.DelegateInput
                ) : async* Types.IssueResult {
                    await* delegateFromScope(boundScope, input);
                };

                release = func(input : Types.ReleaseInput) : () {
                    releaseFromScope(boundScope, input.lease_id);
                };
            };
        };

        public func leaseCountForTesting() : Nat {
            Map.size(leases);
        };

        public func resourceEpochForTesting(
            providerScope : Types.AppScopeRef,
            resource : Types.ResourceRef,
        ) : Nat64 {
            resourceEpoch(providerScope, resource);
        };

        func issueFromScope(
            providerScope : Types.AppScopeRef,
            input : Types.IssueInput,
        ) : async* Types.IssueResult {
            if (not validIssueRequest(providerScope, input)) {
                return #err(#not_authorized);
            };

            let ?initialSubject = scopeSubject(providerScope) else {
                return #err(#not_authorized);
            };
            if (not subjectOwnsScope(initialSubject, providerScope)) {
                return #err(#not_authorized);
            };

            let ?entropy = await* freshGrantEntropy() else {
                return #err(#unavailable);
            };

            // Ownership may change while entropy is acquired. Recompute the
            // current unique owner and validate immediately before persistence.
            if (not validIssueRequest(providerScope, input)) {
                return #err(#not_authorized);
            };
            let ?currentSubject = scopeSubject(providerScope) else {
                return #err(#not_authorized);
            };
            if (not subjectOwnsScope(currentSubject, providerScope)) {
                return #err(#not_authorized);
            };

            createGrantFromEntropy(
                currentSubject,
                providerScope,
                providerScope,
                input.resource,
                input.audience,
                input.consumer_element,
                normalizeRights(input.rights),
                input.expires_at,
                null,
                input.max_redemptions,
                entropy.grant,
                entropy.secret,
            );
        };

        func validIssueRequest(
            providerScope : Types.AppScopeRef,
            input : Types.IssueInput,
        ) : Bool {
            CapabilityScope.valid(providerScope) and
            scopeActive(providerScope) and
            validResource(input.resource) and
            validRights(input.rights) and
            not expiredAtCreation(input.expires_at);
        };

        func listFromScope(
            issuerScope : Types.AppScopeRef,
        ) : [Types.AuthorizationGrant] {
            if (
                not CapabilityScope.valid(issuerScope) or
                not scopeActive(issuerScope)
            ) return [];

            let ?currentSubject = scopeSubject(issuerScope) else return [];

            if (not subjectOwnsScope(currentSubject, issuerScope)) {
                return [];
            };

            let result = List.empty<Types.AuthorizationGrant>();

            for ((_, stored) in Map.entries(grantsMem.grants)) {
                if (
                    CapabilityScope.equal(
                        stored.grant.issuer_scope,
                        issuerScope,
                    ) and
                    stored.grant.issuer_subject == currentSubject
                ) {
                    List.add(result, stored.grant);
                };
            };

            List.toArray(result);
        };

        func revokeFromScope(
            issuerScope : Types.AppScopeRef,
            input : Types.RevokeInput,
        ) : Types.MutationResult {
            if (
                not CapabilityScope.valid(issuerScope) or
                not scopeActive(issuerScope)
            ) return #err(#not_authorized);

            let ?stored = Map.get(
                grantsMem.grants,
                Text.compare,
                input.grant_id,
            ) else return #err(#denied);

            if (
                not CapabilityScope.equal(
                    stored.grant.issuer_scope,
                    issuerScope,
                )
            ) return #err(#not_authorized);

            let ?subject = scopeSubject(issuerScope) else {
                return #err(#not_authorized);
            };

            if (
                not subjectOwnsScope(subject, issuerScope) or
                stored.grant.issuer_subject != subject
            ) return #err(#not_authorized);

            if (stored.grant.revoked_at == null) {
                let revoked =
                    copyGrantWithRevokedAt(stored.grant, ?now());

                Map.add(
                    grantsMem.grants,
                    Text.compare,
                    input.grant_id,
                    {
                        grant = revoked;
                        secret_hash = stored.secret_hash;
                    },
                );

                appendAudit(
                    "revoke",
                    ?input.grant_id,
                    ?subject,
                    null,
                    ?stored.grant.provider_scope,
                    ?stored.grant.resource,
                );
            };

            #ok;
        };

        func rotateResourceFromScope(
            providerScope : Types.AppScopeRef,
            input : Types.RotateResourceInput,
        ) : Types.MutationResult {
            if (
                not CapabilityScope.valid(providerScope) or
                not scopeActive(providerScope) or
                not validResource(input.resource)
            ) return #err(#not_authorized);

            let ?subject = scopeSubject(providerScope) else {
                return #err(#not_authorized);
            };

            if (not subjectOwnsScope(subject, providerScope)) {
                return #err(#not_authorized);
            };

            let key = resourceKey(providerScope, input.resource);
            let current = resourceEpoch(providerScope, input.resource);

            if (current == 18_446_744_073_709_551_615) {
                return #err(#unavailable);
            };

            Map.add(
                epochsMem.epochs,
                Text.compare,
                key,
                current + 1,
            );

            appendAudit(
                "rotate_resource",
                null,
                ?subject,
                null,
                ?providerScope,
                ?input.resource,
            );

            #ok;
        };

        func registerProviderFromScope(
            providerScope : Types.AppScopeRef,
            dispatch : Types.ProviderDispatch,
        ) : () {
            if (
                not CapabilityScope.valid(providerScope) or
                not scopeActive(providerScope)
            ) return;

            let ?subject = scopeSubject(providerScope) else return;
            if (not subjectOwnsScope(subject, providerScope)) return;

            Map.add(
                providerDispatch,
                Text.compare,
                CapabilityScope.key(providerScope),
                dispatch,
            );
        };

        func callFromScope(
            consumerScope : Types.AppScopeRef,
            input : Types.AuthorizedCallInput,
        ) : async* Types.AuthorizedCallResult {
            let ?lease = validLeaseForScope(input.lease_id, consumerScope) else {
                return #denied;
            };
            if (not hasRight(lease.rights, input.requested_right)) return #denied;

            // Both provider scope and exact resource come exclusively from the
            // validated lease. AuthorizedCallInput contains neither field.
            let ?dispatch = Map.get(
                providerDispatch,
                Text.compare,
                CapabilityScope.key(lease.provider_scope),
            ) else return #provider_unavailable;

            let context : Types.AuthorizationContext = {
                grant_id = lease.grant_id;
                lease_id = lease.lease_id;
                subject = lease.subject;
                consumer_scope = lease.consumer_scope;
                provider_scope = lease.provider_scope;
                resource = lease.resource;
                rights = lease.rights;
            };

            let response = await* dispatch({
                authorization = context;
                operation = input.operation;
                payload = input.payload;
            });
            #ok(response);
        };

        func delegateFromScope(
            consumerScope : Types.AppScopeRef,
            input : Types.DelegateInput,
        ) : async* Types.IssueResult {
            let ?lease = validDelegationLease(consumerScope, input) else {
                return #err(#denied);
            };

            let ?entropy = await* freshGrantEntropy() else {
                return #err(#unavailable);
            };

            // The lease, parent, issuer ownership, ancestry, rights and expiry
            // are all revalidated after both randomness awaits. No await occurs
            // between this check and child persistence.
            let ?currentLease = validDelegationLease(consumerScope, input) else {
                return #err(#denied);
            };
            let ?currentParentStored = Map.get(
                grantsMem.grants,
                Text.compare,
                currentLease.grant_id,
            ) else return #err(#denied);
            let currentParent = currentParentStored.grant;

            createGrantFromEntropy(
                currentLease.subject,
                consumerScope,
                currentParent.provider_scope,
                currentParent.resource,
                input.audience,
                input.consumer_element,
                normalizeRights(input.rights),
                input.expires_at,
                ?currentParent.grant_id,
                input.max_redemptions,
                entropy.grant,
                entropy.secret,
            );
        };

        func validDelegationLease(
            consumerScope : Types.AppScopeRef,
            input : Types.DelegateInput,
        ) : ?Types.AuthorizationLease {
            let ?lease = validLeaseForScope(input.lease_id, consumerScope) else {
                return null;
            };
            if (not hasRight(lease.rights, #reshare)) return null;

            let ?parentStored = Map.get(
                grantsMem.grants,
                Text.compare,
                lease.grant_id,
            ) else return null;
            let parent = parentStored.grant;

            if (
                not grantUsable(parent) or
                not validRights(input.rights) or
                not rightsSubset(input.rights, parent.rights) or
                expiredAtCreation(input.expires_at) or
                not childExpiryAllowed(input.expires_at, parent.expires_at) or
                not resourceEqual(lease.resource, parent.resource) or
                not CapabilityScope.equal(
                    lease.provider_scope,
                    parent.provider_scope,
                )
            ) return null;

            ?lease;
        };

        func releaseFromScope(
            consumerScope : Types.AppScopeRef,
            leaseId : Text,
        ) : () {
            switch (Map.get(leases, Text.compare, leaseId)) {
                case (?lease) {
                    if (CapabilityScope.equal(lease.consumer_scope, consumerScope)) {
                        ignore Map.remove(leases, Text.compare, leaseId);
                        appendAudit(
                            "release",
                            ?lease.grant_id,
                            ?lease.subject,
                            ?lease.consumer_scope,
                            ?lease.provider_scope,
                            ?lease.resource,
                        );
                    };
                };
                case null {};
            };
        };

        func freshGrantEntropy() : async* ?{
            grant : Blob;
            secret : Blob;
        } {
            let grantRandom = await* freshRandom();
            let secretRandom = await* freshRandom();
            if (grantRandom.size() < 32 or secretRandom.size() < 32) {
                return null;
            };
            ?{
                grant = grantRandom;
                secret = secretRandom;
            };
        };

        // Synchronous by design. Every caller performs its final authorization
        // revalidation after entropy acquisition before entering this function.
        func createGrantFromEntropy(
            issuerSubject : Types.SubjectRef,
            issuerScope : Types.AppScopeRef,
            providerScope : Types.AppScopeRef,
            resource : Types.ResourceRef,
            audience : Types.GrantAudience,
            consumerElement : ?Text,
            rights : [Types.ResourceRight],
            expiresAt : ?Nat64,
            parentGrantId : ?Text,
            maxRedemptions : ?Nat,
            grantRandom : Blob,
            secretRandom : Blob,
        ) : Types.IssueResult {
            let grantId = hex(grantRandom);
            let secret = hex(secretRandom);

            if (Map.get(grantsMem.grants, Text.compare, grantId) != null) {
                return #err(#unavailable);
            };

            let createdAt = now();
            let grant : Types.AuthorizationGrant = {
                grant_id = grantId;
                issuer_subject = issuerSubject;
                issuer_scope = issuerScope;
                provider_scope = providerScope;
                resource;
                audience;
                consumer_element = consumerElement;
                rights;
                created_at = createdAt;
                expires_at = expiresAt;
                revoked_at = null;
                parent_grant_id = parentGrantId;
                resource_authorization_epoch = resourceEpoch(providerScope, resource);
                max_redemptions = maxRedemptions;
                redemption_count = 0;
            };

            let stored : Types.StoredGrant = {
                grant;
                secret_hash = secretHash(grantId, secret);
            };

            Map.add(grantsMem.grants, Text.compare, grantId, stored);
            appendAudit(
                if (parentGrantId == null) "issue" else "delegate",
                ?grantId,
                ?issuerSubject,
                null,
                ?providerScope,
                ?resource,
            );

            #ok({
                grant;
                token = TOKEN_PREFIX # "_" # grantId # "_" # secret;
            });
        };

        func validLeaseForScope(
            leaseId : Text,
            consumerScope : Types.AppScopeRef,
        ) : ?Types.AuthorizationLease {
            let ?lease = Map.get(leases, Text.compare, leaseId) else return null;
            if (
                lease.expires_at <= now() or
                not CapabilityScope.equal(lease.consumer_scope, consumerScope) or
                not scopeActive(consumerScope) or
                not subjectOwnsScope(lease.subject, consumerScope)
            ) return null;

            let ?stored = Map.get(
                grantsMem.grants,
                Text.compare,
                lease.grant_id,
            ) else return null;
            if (not grantUsable(stored.grant)) return null;

            ?lease;
        };

        func grantUsable(grant : Types.AuthorizationGrant) : Bool {
            if (
                grant.revoked_at != null or
                isExpired(grant.expires_at) or
                not grantEpochCurrent(grant) or
                not scopeActive(grant.provider_scope) or
                not scopeActive(grant.issuer_scope) or
                not subjectOwnsScope(grant.issuer_subject, grant.issuer_scope)
            ) return false;

            ancestryUsable(grant, grant, 0);
        };

        func ancestryUsable(
            original : Types.AuthorizationGrant,
            current : Types.AuthorizationGrant,
            depth : Nat,
        ) : Bool {
            switch (current.parent_grant_id) {
                case null true;
                case (?parentId) {
                    if (depth >= MAX_ANCESTRY_DEPTH) return false;
                    let ?parentStored = Map.get(
                        grantsMem.grants,
                        Text.compare,
                        parentId,
                    ) else return false;
                    let parent = parentStored.grant;

                    if (
                        parent.revoked_at != null or
                        isExpired(parent.expires_at) or
                        not grantEpochCurrent(parent) or
                        not scopeActive(parent.provider_scope) or
                        not scopeActive(parent.issuer_scope) or
                        not subjectOwnsScope(
                            parent.issuer_subject,
                            parent.issuer_scope,
                        ) or
                        not resourceEqual(parent.resource, original.resource) or
                        not CapabilityScope.equal(
                            parent.provider_scope,
                            original.provider_scope,
                        )
                    ) return false;

                    ancestryUsable(original, parent, depth + 1);
                };
            };
        };

        func effectivelyRevoked(grant : Types.AuthorizationGrant) : Bool {
            if (
                grant.revoked_at != null or
                not grantEpochCurrent(grant) or
                not scopeActive(grant.provider_scope) or
                not scopeActive(grant.issuer_scope) or
                not subjectOwnsScope(grant.issuer_subject, grant.issuer_scope)
            ) return true;

            ancestryEffectivelyRevoked(grant, grant, 0);
        };

        func ancestryEffectivelyRevoked(
            original : Types.AuthorizationGrant,
            current : Types.AuthorizationGrant,
            depth : Nat,
        ) : Bool {
            switch (current.parent_grant_id) {
                case null false;
                case (?parentId) {
                    if (depth >= MAX_ANCESTRY_DEPTH) return true;
                    let ?parentStored = Map.get(
                        grantsMem.grants,
                        Text.compare,
                        parentId,
                    ) else return true;
                    let parent = parentStored.grant;

                    if (
                        parent.revoked_at != null or
                        not grantEpochCurrent(parent) or
                        not scopeActive(parent.provider_scope) or
                        not scopeActive(parent.issuer_scope) or
                        not subjectOwnsScope(
                            parent.issuer_subject,
                            parent.issuer_scope,
                        ) or
                        not resourceEqual(parent.resource, original.resource) or
                        not CapabilityScope.equal(
                            parent.provider_scope,
                            original.provider_scope,
                        )
                    ) return true;

                    ancestryEffectivelyRevoked(original, parent, depth + 1);
                };
            };
        };

        func grantEpochCurrent(grant : Types.AuthorizationGrant) : Bool {
            grant.resource_authorization_epoch ==
                resourceEpoch(grant.provider_scope, grant.resource);
        };

        func resourceEpoch(
            providerScope : Types.AppScopeRef,
            resource : Types.ResourceRef,
        ) : Nat64 {
            switch (
                Map.get(
                    epochsMem.epochs,
                    Text.compare,
                    resourceKey(providerScope, resource),
                )
            ) {
                case (?value) value;
                case null 0;
            };
        };

        func resourceKey(
            providerScope : Types.AppScopeRef,
            resource : Types.ResourceRef,
        ) : Text {
            CapabilityScope.key(providerScope) # "\00" #
            resource.namespace # "\00" # resource.resource_id # "\00" #
            resource.resource_type;
        };

        func consumerElementAllows(
            required : ?Text,
            scope : Types.AppScopeRef,
        ) : Bool {
            switch (required) {
                case null true;
                case (?element) {
                    switch (scopeElement(scope)) {
                        case (?actual) actual == element;
                        case null false;
                    };
                };
            };
        };

        func audienceAllows(
            audience : Types.GrantAudience,
            subject : Types.SubjectRef,
        ) : Bool {
            switch (audience, subject) {
                case (#any_authenticated, #principal(principal)) {
                    not isAnonymous(principal);
                };
                case (#principal(expected), #principal(actual)) expected == actual;
            };
        };

        func redemptionAvailable(grant : Types.AuthorizationGrant) : Bool {
            switch (grant.max_redemptions) {
                case null true;
                case (?maximum) grant.redemption_count < maximum;
            };
        };

        func childExpiryAllowed(child : ?Nat64, parent : ?Nat64) : Bool {
            switch (parent) {
                case null true;
                case (?parentExpiry) {
                    switch (child) {
                        case (?childExpiry) childExpiry <= parentExpiry;
                        case null false;
                    };
                };
            };
        };

        func expiredAtCreation(value : ?Nat64) : Bool {
            switch (value) {
                case (?expiry) expiry <= now();
                case null false;
            };
        };

        func isExpired(value : ?Nat64) : Bool {
            switch (value) {
                case (?expiry) expiry <= now();
                case null false;
            };
        };

        func validResource(resource : Types.ResourceRef) : Bool {
            resource.namespace.size() > 0 and resource.namespace.size() <= 128 and
            resource.resource_id.size() > 0 and resource.resource_id.size() <= 512 and
            resource.resource_type.size() > 0 and resource.resource_type.size() <= 128;
        };

        func validRights(rights : [Types.ResourceRight]) : Bool {
            rights.size() > 0 and rights.size() <= 3;
        };

        func normalizeRights(
            rights : [Types.ResourceRight],
        ) : [Types.ResourceRight] {
            let allRights : [Types.ResourceRight] = [#read, #write, #reshare];
            Array.filter<Types.ResourceRight>(
                allRights,
                func(right : Types.ResourceRight) : Bool {
                    hasRight(rights, right);
                },
            );
        };

        func rightsSubset(
            child : [Types.ResourceRight],
            parent : [Types.ResourceRight],
        ) : Bool {
            for (right in child.vals()) {
                if (not hasRight(parent, right)) return false;
            };
            true;
        };

        func hasRight(
            rights : [Types.ResourceRight],
            requested : Types.ResourceRight,
        ) : Bool {
            for (right in rights.vals()) {
                if (right == requested) return true;
            };
            false;
        };

        func resourceEqual(
            left : Types.ResourceRef,
            right : Types.ResourceRef,
        ) : Bool {
            left.namespace == right.namespace and
            left.resource_id == right.resource_id and
            left.resource_type == right.resource_type;
        };

        func parseToken(value : Text) : ?{ grant_id : Text; secret : Text } {
            let parts = Iter.toArray(Text.split(value, #char '_'));
            if (parts.size() != 3 or parts[0] != TOKEN_PREFIX) return null;
            if (parts[1].size() != 64 or parts[2].size() != 64) return null;
            if (not isLowerHex(parts[1]) or not isLowerHex(parts[2])) return null;
            ?{ grant_id = parts[1]; secret = parts[2] };
        };

        func isLowerHex(value : Text) : Bool {
            for (char in value.chars()) {
                if (
                    not ((char >= '0' and char <= '9') or
                    (char >= 'a' and char <= 'f'))
                ) return false;
            };
            true;
        };

        func secretHash(grantId : Text, secret : Text) : Blob {
            Sha256.fromBlob(
                #sha256,
                Text.encodeUtf8(SECRET_HASH_DOMAIN # grantId # "\00" # secret),
            );
        };

        func secretMatches(
            grantId : Text,
            secret : Text,
            expected : Blob,
        ) : Bool {
            Blob.equal(secretHash(grantId, secret), expected);
        };

        func hex(value : Blob) : Text {
            var result = "";
            for (byte in value.vals()) {
                let natural = Nat8.toNat(byte);
                result #= LOWER_HEX_DIGITS[natural / 16] #
                    LOWER_HEX_DIGITS[natural % 16];
            };
            result;
        };

        func appendAudit(
            kind : Text,
            grantId : ?Text,
            subject : ?Types.SubjectRef,
            consumerScope : ?Types.AppScopeRef,
            providerScope : ?Types.AppScopeRef,
            resource : ?Types.ResourceRef,
        ) : () {
            let id = auditMem.next_id;
            if (id == 18_446_744_073_709_551_615) return;
            let event : Types.AuditEvent = {
                id;
                at = now();
                kind;
                grant_id = grantId;
                subject;
                consumer_scope = consumerScope;
                provider_scope = providerScope;
                resource;
            };
            Map.add(auditMem.events, Nat64.compare, id, event);
            auditMem.next_id += 1;
        };

        func copyGrantWithRedemptionCount(
            grant : Types.AuthorizationGrant,
            count : Nat,
        ) : Types.AuthorizationGrant {
            {
                grant_id = grant.grant_id;
                issuer_subject = grant.issuer_subject;
                issuer_scope = grant.issuer_scope;
                provider_scope = grant.provider_scope;
                resource = grant.resource;
                audience = grant.audience;
                consumer_element = grant.consumer_element;
                rights = grant.rights;
                created_at = grant.created_at;
                expires_at = grant.expires_at;
                revoked_at = grant.revoked_at;
                parent_grant_id = grant.parent_grant_id;
                resource_authorization_epoch = grant.resource_authorization_epoch;
                max_redemptions = grant.max_redemptions;
                redemption_count = count;
            };
        };

        func copyGrantWithRevokedAt(
            grant : Types.AuthorizationGrant,
            revokedAt : ?Nat64,
        ) : Types.AuthorizationGrant {
            {
                grant_id = grant.grant_id;
                issuer_subject = grant.issuer_subject;
                issuer_scope = grant.issuer_scope;
                provider_scope = grant.provider_scope;
                resource = grant.resource;
                audience = grant.audience;
                consumer_element = grant.consumer_element;
                rights = grant.rights;
                created_at = grant.created_at;
                expires_at = grant.expires_at;
                revoked_at = revokedAt;
                parent_grant_id = grant.parent_grant_id;
                resource_authorization_epoch = grant.resource_authorization_epoch;
                max_redemptions = grant.max_redemptions;
                redemption_count = grant.redemption_count;
            };
        };
    };
};
