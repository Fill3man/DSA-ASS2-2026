import ballerina/time;
import ballerinax/kafka;
import ballerinax/mongodb;

// Keeps admin_db.order_facts up to date: one document per order with a
// timestamp for every stage. Stored twice - ISO string for people, epoch
// milliseconds for the aggregation maths in reports.bal.

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection facts = check getFacts();

isolated function getFacts() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("order_facts");
}

listener kafka:Listener eventListener = new (kafkaBootstrap, {
    groupId: SERVICE_NAME,
    clientId: SERVICE_NAME + "-consumer",
    topics: [TOPIC_ORDERS_CREATED, TOPIC_ORDERS_STATUS_CHANGED, TOPIC_DELIVERY_ASSIGNED],
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

// Which timestamp field each status stamps.
final readonly & map<string> stampFields = {
    [CONFIRMED]: "confirmedAt",
    [PREPARING]: "preparingAt",
    [READY]: "readyAt",
    [OUT_FOR_DELIVERY]: "pickedUpAt",
    [DELIVERED]: "deliveredAt",
    [CANCELLED]: "cancelledAt"
};

isolated function handleEvent(string topic, json payload) returns error? {
    if topic == TOPIC_ORDERS_CREATED {
        OrderCreatedEvent e = check payload.cloneWithType();
        // setOnInsert: if a status-changed event got here first, don't
        // overwrite its newer status with CREATED.
        _ = check facts->updateOne({orderId: e.orderId}, {
            set: {
                restaurantId: e.restaurantId,
                customerId: e.customerId,
                totalAmount: e.totalAmount,
                createdAt: e.occurredAt,
                createdAtMs: check epochMs(e.occurredAt)
            },
            setOnInsert: {status: CREATED}
        }, {upsert: true});

    } else if topic == TOPIC_ORDERS_STATUS_CHANGED {
        OrderStatusChangedEvent e = check payload.cloneWithType();
        map<json> fields = {restaurantId: e.restaurantId, customerId: e.customerId, status: e.toStatus};
        string? stamp = stampFields[e.toStatus];
        if stamp is string {
            fields[stamp] = e.occurredAt;
            fields[stamp + "Ms"] = check epochMs(e.occurredAt);
        }
        string? driverId = e.driverId;
        if driverId is string {
            fields["driverId"] = driverId;
        }
        _ = check facts->updateOne({orderId: e.orderId}, {set: fields}, {upsert: true});

    } else if topic == TOPIC_DELIVERY_ASSIGNED {
        DeliveryAssignedEvent e = check payload.cloneWithType();
        mongodb:UpdateResult r = check facts->updateOne({orderId: e.orderId}, {set: {driverId: e.driverId}});
        if r.matchedCount == 0 {
            // orders.created hasn't been processed yet - fail so it is retried.
            return error(string `no facts yet for ${e.orderId}`);
        }
    }
}

isolated function epochMs(string iso) returns int|error {
    time:Utc t = check time:utcFromString(iso);
    return t[0] * 1000 + <int>(t[1] * 1000);
}
