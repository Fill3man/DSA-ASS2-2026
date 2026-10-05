import ballerina/test;

@test:Config {}
function happyPathIsAllowed() {
    OrderStatus[] path = [CREATED, CONFIRMED, PREPARING, READY, OUT_FOR_DELIVERY, DELIVERED];
    foreach int i in 0 ..< path.length() - 1 {
        test:assertTrue(canTransition(path[i], path[i + 1]), string `${path[i]} -> ${path[i + 1]}`);
    }
}

@test:Config {}
function cancellationOnlyBeforePickup() {
    test:assertTrue(canTransition(CREATED, CANCELLED));
    test:assertTrue(canTransition(CONFIRMED, CANCELLED));
    test:assertTrue(canTransition(PREPARING, CANCELLED));
    test:assertFalse(canTransition(READY, CANCELLED));
    test:assertFalse(canTransition(OUT_FOR_DELIVERY, CANCELLED));
}

@test:Config {}
function cannotSkipStates() {
    test:assertFalse(canTransition(CREATED, PREPARING));
    test:assertFalse(canTransition(CONFIRMED, READY));
    test:assertFalse(canTransition(PREPARING, DELIVERED));
}

@test:Config {}
function terminalStatesHaveNoExit() {
    OrderStatus[] all = [CREATED, CONFIRMED, PREPARING, READY, OUT_FOR_DELIVERY, DELIVERED, CANCELLED];
    foreach OrderStatus s in all {
        test:assertFalse(canTransition(DELIVERED, s));
        test:assertFalse(canTransition(CANCELLED, s));
    }
    test:assertTrue(isTerminal(DELIVERED));
    test:assertTrue(isTerminal(CANCELLED));
}

@test:Config {}
function validateTransitionReturnsTypedError() {
    test:assertTrue(validateTransition(READY, CREATED) is InvalidTransitionError);
    test:assertTrue(validateTransition(READY, OUT_FOR_DELIVERY) is ());
}
