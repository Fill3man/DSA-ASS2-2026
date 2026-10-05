// The order state machine.
//
//   CREATED -> CONFIRMED -> PREPARING -> READY -> OUT_FOR_DELIVERY -> DELIVERED
//      |           |            |
//      +-----------+------------+--> CANCELLED
//
// DELIVERED and CANCELLED are terminal.

final readonly & map<OrderStatus[]> allowedTransitions = {
    [CREATED]: [CONFIRMED, CANCELLED],
    [CONFIRMED]: [PREPARING, CANCELLED],
    [PREPARING]: [READY, CANCELLED],
    [READY]: [OUT_FOR_DELIVERY],
    [OUT_FOR_DELIVERY]: [DELIVERED],
    [DELIVERED]: [],
    [CANCELLED]: []
};

// Statuses that a restaurant may set directly through PATCH /orders/{id}/status.
// The others are driven by events: CONFIRMED by payments.completed,
// OUT_FOR_DELIVERY by delivery.picked-up, DELIVERED by delivery.completed.
final readonly & OrderStatus[] restaurantSettableStatuses = [PREPARING, READY, CANCELLED];

// Statuses from which a customer may still cancel.
final readonly & OrderStatus[] customerCancellableStatuses = [CREATED, CONFIRMED];

public isolated function canTransition(OrderStatus 'from, OrderStatus to) returns boolean {
    OrderStatus[]? next = allowedTransitions['from];
    return next is OrderStatus[] && next.indexOf(to) != ();
}

public isolated function isTerminal(OrderStatus status) returns boolean {
    return status == DELIVERED || status == CANCELLED;
}

public isolated function validateTransition(OrderStatus 'from, OrderStatus to) returns InvalidTransitionError? {
    if !canTransition('from, to) {
        return error InvalidTransitionError(string `cannot move order from ${'from} to ${to}`);
    }
}
