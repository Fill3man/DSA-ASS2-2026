import ballerina/log;
import ballerina/uuid;

const MAX_CAS_ATTEMPTS = 3;

isolated function createOrder(CreateOrderRequest req) returns Order|error {
    decimal total = 0;
    foreach OrderItem item in req.items {
        total += item.unitPrice * <decimal>item.quantity;
    }
    string now = nowIso();
    Order 'order = {
        orderId: "ord-" + uuid:createType4AsString(),
        customerId: req.customerId,
        restaurantId: req.restaurantId,
        items: req.items,
        totalAmount: total,
        currency,
        deliveryAddress: req.deliveryAddress,
        status: CREATED,
        statusHistory: [{status: CREATED, at: now, triggeredBy: "customer"}],
        createdAt: now,
        updatedAt: now
    };
    check insertOrder('order);
    // If this publish fails the order exists but nobody hears about it. A
    // transactional outbox would close that gap - see docs/ARCHITECTURE.md.
    check publishOrderCreated('order);
    log:printInfo("order created", orderId = 'order.orderId, total = total);
    return 'order;
}

// Moves an order to `target`, persisting the change and publishing events.
//
// Idempotent: if the order is already in `target` the current order is
// returned unchanged and no event is published. That makes it safe to call
// from Kafka consumers, where at-least-once delivery means duplicates happen.
// `extraFields` are written in the same update (e.g. paymentId).
isolated function transitionOrder(string orderId, OrderStatus target, string triggeredBy,
        string? reason = (), map<json> extraFields = {}) returns Order|error {
    foreach int attempt in 1 ... MAX_CAS_ATTEMPTS {
        Order current = check findOrder(orderId);
        if current.status == target {
            return current;
        }
        check validateTransition(current.status, target);

        StatusChange change = {status: target, at: nowIso(), triggeredBy, reason};
        boolean updated = check updateStatusIfCurrent(orderId, current.status, change, extraFields);
        if !updated {
            log:printDebug("order changed concurrently, retrying", orderId = orderId, attempt = attempt);
            continue;
        }

        Order next = check findOrder(orderId);
        check publishStatusChanged(next, current.status, change);
        log:printInfo("order status changed", orderId = orderId, 'from = current.status, to = target,
                triggeredBy = triggeredBy);
        return next;
    }
    return error ConcurrentUpdateError(string `order ${orderId} kept changing; gave up after ${MAX_CAS_ATTEMPTS} attempts`);
}
