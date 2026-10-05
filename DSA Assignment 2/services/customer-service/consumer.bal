import ballerinax/kafka;

// Builds the customer's order-history read model from order events, so that
// GET /customers/{id}/orders never has to call order-service.

listener kafka:Listener eventListener = new (kafkaBootstrap, {
    groupId: SERVICE_NAME,
    clientId: SERVICE_NAME + "-consumer",
    topics: [TOPIC_ORDERS_CREATED, TOPIC_ORDERS_STATUS_CHANGED],
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
        check recordOrderCreated(e);
    } else if topic == TOPIC_ORDERS_STATUS_CHANGED {
        OrderStatusChangedEvent e = check payload.cloneWithType();
        check recordStatusChange(e);
    }
}
