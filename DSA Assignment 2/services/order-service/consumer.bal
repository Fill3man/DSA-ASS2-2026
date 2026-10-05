import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/kafka;

// Order service reacts to events from payment, restaurant and delivery services.
// One consumer group ("order-service") means each event is handled by exactly
// one order-service replica; partitions are spread across replicas.

listener kafka:Listener orderEventListener = new (kafkaBootstrap, {
    groupId: "order-service",
    clientId: "order-service-consumer",
    topics: [
        TOPIC_PAYMENTS_COMPLETED,
        TOPIC_PAYMENTS_FAILED,
        TOPIC_RESTAURANTS_ORDER_REJECTED,
        TOPIC_DELIVERY_ASSIGNED,
        TOPIC_DELIVERY_PICKED_UP,
        TOPIC_DELIVERY_COMPLETED
    ],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    // Offsets are committed manually, after processing, so a crash
    // mid-batch replays the events instead of losing them.
    autoCommit: false,
    pollingInterval: 1
});

service on orderEventListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            processRecord(rec);
        }
        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("failed to commit offsets", commitResult);
        }
    }

    remote function onError(kafka:Error kafkaError) {
        log:printError("kafka listener error", kafkaError);
    }
}

isolated function processRecord(kafka:BytesConsumerRecord rec) {
    string topic = rec.offset.partition.topic;
    string|error raw = string:fromBytes(rec.value);
    json|error payload = raw is string ? raw.fromJsonString() : raw;
    if payload is error {
        // Poison message: retrying will never help.
        deadLetter(rec, raw is string ? raw : "<non-utf8>", payload);
        return;
    }

    error? lastError = ();
    foreach int attempt in 1 ... maxEventRetries {
        lastError = handleEvent(topic, payload);
        if lastError is () {
            return;
        }
        if lastError is InvalidTransitionError|OrderNotFoundError {
            // Business-level rejection: log it, don't retry or dead-letter.
            log:printWarn("event ignored", topic = topic, reason = lastError.message());
            return;
        }
        log:printWarn("event handling failed, retrying", topic = topic, attempt = attempt,
                reason = lastError.message());
        runtime:sleep(<decimal>attempt * 0.5);
    }
    deadLetter(rec, payload.toJsonString(), <error>lastError);
}

isolated function handleEvent(string topic, json payload) returns error? {
    match topic {
        TOPIC_PAYMENTS_COMPLETED => {
            PaymentCompletedEvent e = check payload.cloneWithType();
            _ = check transitionOrder(e.orderId, CONFIRMED, "payment-service", (), {paymentId: e.paymentId});
        }
        TOPIC_PAYMENTS_FAILED => {
            PaymentFailedEvent e = check payload.cloneWithType();
            _ = check transitionOrder(e.orderId, CANCELLED, "payment-service", "payment failed: " + e.reason,
                    {paymentId: e.paymentId});
        }
        TOPIC_RESTAURANTS_ORDER_REJECTED => {
            OrderRejectedEvent e = check payload.cloneWithType();
            _ = check transitionOrder(e.orderId, CANCELLED, "restaurant-service", "rejected: " + e.reason);
        }
        TOPIC_DELIVERY_ASSIGNED => {
            // Driver assignment doesn't change the order status; just record who is coming.
            DeliveryAssignedEvent e = check payload.cloneWithType();
            boolean found = check setOrderFields(e.orderId,
                    {deliveryId: e.deliveryId, driverId: e.driverId, updatedAt: nowIso()});
            if !found {
                return error OrderNotFoundError(string `order ${e.orderId} not found`);
            }
        }
        TOPIC_DELIVERY_PICKED_UP => {
            DeliveryPickedUpEvent e = check payload.cloneWithType();
            _ = check transitionOrder(e.orderId, OUT_FOR_DELIVERY, "delivery-service", (),
                    {deliveryId: e.deliveryId, driverId: e.driverId});
        }
        TOPIC_DELIVERY_COMPLETED => {
            DeliveryCompletedEvent e = check payload.cloneWithType();
            _ = check transitionOrder(e.orderId, DELIVERED, "delivery-service");
        }
        _ => {
            log:printWarn("received event from unexpected topic", topic = topic);
        }
    }
}

isolated function deadLetter(kafka:BytesConsumerRecord rec, string rawValue, error cause) {
    log:printError("sending event to dead-letter topic", cause, topic = rec.offset.partition.topic,
            offset = rec.offset.offset);
    publishDeadLetter({
        failedAt: nowIso(),
        sourceTopic: rec.offset.partition.topic,
        sourcePartition: rec.offset.partition.partition,
        sourceOffset: rec.offset.offset,
        errorMessage: cause.message(),
        rawValue
    });
}
