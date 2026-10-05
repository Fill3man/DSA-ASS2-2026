import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;

// acks=all + idempotence: the broker only acknowledges once the write is
// durable, and retried sends never create duplicates on the topic.
final kafka:Producer producer = check new (kafkaBootstrap, {
    clientId: "order-service",
    acks: kafka:ACKS_ALL,
    enableIdempotence: true,
    retryCount: 5
});

isolated function newEventId() returns string => uuid:createType4AsString();

isolated function nowIso() returns string => time:utcToString(time:utcNow());

// Publishes `event` as JSON with the given key (orderId for order-scoped events).
isolated function publish(string topic, string key, anydata event) returns error? {
    check producer->send({
        topic,
        key: key.toBytes(),
        value: event.toJsonString().toBytes()
    });
    log:printDebug("event published", topic = topic, key = key);
}

isolated function publishOrderCreated(Order o) returns error? {
    OrderCreatedEvent event = {
        eventId: newEventId(),
        occurredAt: nowIso(),
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        items: o.items,
        totalAmount: o.totalAmount,
        currency: o.currency,
        deliveryAddress: o.deliveryAddress
    };
    check publish(TOPIC_ORDERS_CREATED, o.orderId, event);
}

isolated function publishStatusChanged(Order o, OrderStatus fromStatus, StatusChange change) returns error? {
    OrderStatusChangedEvent event = {
        eventId: newEventId(),
        occurredAt: change.at,
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        driverId: o.driverId,
        fromStatus,
        toStatus: change.status,
        triggeredBy: change.triggeredBy,
        reason: change.reason
    };
    check publish(TOPIC_ORDERS_STATUS_CHANGED, o.orderId, event);

    if change.status == CANCELLED {
        OrderCancelledEvent cancelled = {
            eventId: newEventId(),
            occurredAt: change.at,
            orderId: o.orderId,
            customerId: o.customerId,
            restaurantId: o.restaurantId,
            paymentId: o.paymentId,
            totalAmount: o.totalAmount,
            reason: change.reason
        };
        check publish(TOPIC_ORDERS_CANCELLED, o.orderId, cancelled);
    }
}

isolated function publishDeadLetter(DeadLetter letter) {
    error? result = publish(TOPIC_ORDERS_DLQ, letter.sourceTopic, letter);
    if result is error {
        log:printError("could not write to dead-letter topic", result, letter = letter.toString());
    }
}
