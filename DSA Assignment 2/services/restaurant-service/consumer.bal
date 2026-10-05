import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener eventListener = new (kafkaBootstrap, {
    groupId: SERVICE_NAME,
    clientId: SERVICE_NAME + "-consumer",
    topics: [TOPIC_ORDERS_CREATED, TOPIC_ORDERS_CANCELLED],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false,
    pollingInterval: 1
});

service on eventListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) {
        foreach kafka:BytesConsumerRecord rec in records {
            processRecord(rec);
        }
        commitBatch(caller);
    }
}

isolated function handleEvent(string topic, json payload) returns error? {
    if topic == TOPIC_ORDERS_CREATED {
        OrderCreatedEvent e = check payload.cloneWithType();
        check reserveForOrder(e);
    } else if topic == TOPIC_ORDERS_CANCELLED {
        OrderCancelledEvent e = check payload.cloneWithType();
        check releaseForOrder(e.orderId);
    }
}

// Accept or reject a new order: the restaurant must exist and be open, and
// every item must be available with enough stock.
isolated function reserveForOrder(OrderCreatedEvent e) returns error? {
    if check findReservation(e.orderId) is Reservation {
        return; // already decided - redelivered event
    }

    Restaurant|error restaurant = findRestaurant(e.restaurantId);
    if restaurant is NotFoundError {
        return reject(e, "unknown restaurant");
    }
    Restaurant r = check restaurant;
    if !acceptsOrders(r) {
        return reject(e, string `${r.name} is closed right now`);
    }

    ReservedItem[] taken = [];
    foreach OrderItem item in e.items {
        if !check takeStock(e.restaurantId, item.itemId, item.quantity) {
            // Undo what we already took, then reject the whole order.
            foreach ReservedItem t in taken {
                check returnStock(e.restaurantId, t.itemId, t.quantity);
            }
            return reject(e, string `${item.name} is unavailable or out of stock`);
        }
        taken.push({itemId: item.itemId, quantity: item.quantity});
    }

    check insertReservation({orderId: e.orderId, restaurantId: e.restaurantId, items: taken,
        status: RESERVED, createdAt: nowIso()});
    check publish(TOPIC_RESTAURANTS_ORDER_ACCEPTED, e.orderId, <OrderAcceptedEvent>{
        eventId: newEventId(),
        occurredAt: nowIso(),
        orderId: e.orderId,
        restaurantId: r.restaurantId,
        restaurantName: r.name,
        pickupLatitude: r.location.latitude,
        pickupLongitude: r.location.longitude
    });
    log:printInfo("order accepted, stock reserved", orderId = e.orderId, items = taken.length());
}

isolated function reject(OrderCreatedEvent e, string reason) returns error? {
    error? saved = insertReservation({orderId: e.orderId, restaurantId: e.restaurantId, items: [],
        status: REJECTED, reason, createdAt: nowIso()});
    if saved is error && !isDuplicateKey(saved) {
        return saved;
    }
    check publish(TOPIC_RESTAURANTS_ORDER_REJECTED, e.orderId, <OrderRejectedEvent>{
        eventId: newEventId(),
        occurredAt: nowIso(),
        orderId: e.orderId,
        restaurantId: e.restaurantId,
        reason
    });
    log:printWarn("order rejected", orderId = e.orderId, reason = reason);
}

// Give the stock back - only once, and only if it was actually taken.
isolated function releaseForOrder(string orderId) returns error? {
    Reservation? r = check findReservation(orderId);
    if r is () || !check releaseReservation(orderId) {
        return;
    }
    foreach ReservedItem item in r.items {
        check returnStock(r.restaurantId, item.itemId, item.quantity);
    }
    log:printInfo("order cancelled, stock returned", orderId = orderId);
}
