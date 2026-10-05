import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener eventListener = new (kafkaBootstrap, {
    groupId: SERVICE_NAME,
    clientId: SERVICE_NAME + "-consumer",
    topics: [TOPIC_ORDERS_CREATED, TOPIC_RESTAURANTS_ORDER_ACCEPTED, TOPIC_ORDERS_STATUS_CHANGED],
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
        map<json> fields = {
            restaurantId: e.restaurantId,
            customerId: e.customerId,
            dropoffAddress: e.deliveryAddress.street + ", " + e.deliveryAddress.city
        };
        float? lat = e.deliveryAddress.latitude;
        float? lon = e.deliveryAddress.longitude;
        if lat is float && lon is float {
            fields["dropoff"] = {latitude: lat, longitude: lon};
        }
        check upsertDelivery(e.orderId, fields);

    } else if topic == TOPIC_RESTAURANTS_ORDER_ACCEPTED {
        OrderAcceptedEvent e = check payload.cloneWithType();
        check upsertDelivery(e.orderId, {
            restaurantName: e.restaurantName,
            pickup: {latitude: e.pickupLatitude, longitude: e.pickupLongitude}
        });
        check tryAssign(e.orderId);

    } else if topic == TOPIC_ORDERS_STATUS_CHANGED {
        OrderStatusChangedEvent e = check payload.cloneWithType();
        check upsertDelivery(e.orderId, {orderStatus: e.toStatus});
        if e.toStatus == CONFIRMED {
            check tryAssign(e.orderId);
        } else if e.toStatus == CANCELLED {
            check cancelDelivery(e.orderId, e.reason ?: "order cancelled");
        } else if e.toStatus == DELIVERED {
            check reconcileDelivered(e.orderId);
        }
    }
}

// Normally a delivery reaches DELIVERED through POST /deliveries/{id}/complete.
// If the order was completed some other way (e.g. an operator fixed it by
// hand), bring our record in line and free the driver instead of leaving
// them BUSY forever.
isolated function reconcileDelivered(string orderId) returns error? {
    Delivery d = check findDelivery({orderId});
    if d.status != ASSIGNED && d.status != PICKED_UP {
        return;
    }
    if check updateDeliveryIf(orderId, d.status, {status: DELIVERED, deliveredAt: nowIso()}) {
        string? driverId = d?.driverId;
        if driverId is string {
            _ = check setDriverStatusIf(driverId, BUSY, AVAILABLE);
            log:printWarn("order delivered outside delivery-service, driver released", orderId = orderId,
                    driverId = driverId);
            assignQueued();
        }
    }
}

isolated function cancelDelivery(string orderId, string reason) returns error? {
    Delivery d = check findDelivery({orderId});
    if d.status == PENDING_DRIVER {
        _ = check updateDeliveryIf(orderId, PENDING_DRIVER, {status: FAILED, failureReason: reason});
    } else if d.status == ASSIGNED {
        if check updateDeliveryIf(orderId, ASSIGNED, {status: FAILED, failureReason: reason}) {
            string? driverId = d?.driverId;
            if driverId is string {
                _ = check setDriverStatusIf(driverId, BUSY, AVAILABLE);
                log:printInfo("order cancelled, driver released", orderId = orderId, driverId = driverId);
                assignQueued();
            }
        }
    }
}
