import ballerina/log;
import ballerinax/kafka;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection notifications = check getNotifications();

isolated function getNotifications() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("notifications");
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

isolated function handleEvent(string topic, json payload) returns error? {
    string eventId;
    string orderId;
    string eventType;
    Alert[] alerts;

    if topic == TOPIC_ORDERS_CREATED {
        OrderCreatedEvent e = check payload.cloneWithType();
        [eventId, orderId, eventType] = [e.eventId, e.orderId, e.eventType];
        alerts = [...alertsForCreated(e), ...inAppForCreated(e)];
    } else if topic == TOPIC_ORDERS_STATUS_CHANGED {
        OrderStatusChangedEvent e = check payload.cloneWithType();
        [eventId, orderId, eventType] = [e.eventId, e.orderId, e.eventType + ":" + e.toStatus];
        alerts = [...alertsForStatus(e), ...inAppForStatus(e)];
    } else if topic == TOPIC_DELIVERY_ASSIGNED {
        DeliveryAssignedEvent e = check payload.cloneWithType();
        [eventId, orderId, eventType] = [e.eventId, e.orderId, e.eventType];
        alerts = [
            {recipientType: DRIVER, recipientId: e.driverId, channel: PUSH,
                message: string `New delivery for order ${short(e.orderId)}. Estimated trip: ${e.etaMinutes ?: 0} min.`},
            ...check inAppForAssigned(e)
        ];
    } else {
        return;
    }

    foreach Alert a in alerts {
        check send(eventId, orderId, eventType, a);
    }
}

isolated function alertsForCreated(OrderCreatedEvent e) returns Alert[] {
    int count = 0;
    foreach OrderItem i in e.items {
        count += i.quantity;
    }
    return [
        {recipientType: RESTAURANT, recipientId: e.restaurantId, channel: PUSH,
            message: string `New order ${short(e.orderId)}: ${count} item(s), ${e.currency} ${e.totalAmount.round(2)}.`},
        {recipientType: CUSTOMER, recipientId: e.customerId, channel: EMAIL,
            message: string `We received your order ${short(e.orderId)} (${e.currency} ${e.totalAmount.round(2)}). Processing payment...`}
    ];
}

isolated function alertsForStatus(OrderStatusChangedEvent e) returns Alert[] {
    string id = short(e.orderId);
    Alert[] alerts = [];
    match e.toStatus {
        CONFIRMED => {
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: EMAIL,
                message: string `Payment received - order ${id} is confirmed.`});
        }
        PREPARING => {
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: PUSH,
                message: string `The kitchen has started on order ${id}.`});
        }
        READY => {
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: PUSH,
                message: string `Order ${id} is ready and waiting for the driver.`});
            string? driverId = e.driverId;
            if driverId is string {
                alerts.push({recipientType: DRIVER, recipientId: driverId, channel: PUSH,
                    message: string `Order ${id} is ready for pickup.`});
            }
        }
        OUT_FOR_DELIVERY => {
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: SMS,
                message: string `Your order ${id} is on its way!`});
        }
        DELIVERED => {
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: SMS,
                message: string `Order ${id} delivered. Enjoy your meal!`});
            alerts.push({recipientType: RESTAURANT, recipientId: e.restaurantId, channel: PUSH,
                message: string `Order ${id} was delivered.`});
        }
        CANCELLED => {
            string reason = e.reason ?: "no reason given";
            alerts.push({recipientType: CUSTOMER, recipientId: e.customerId, channel: SMS,
                message: string `Order ${id} was cancelled: ${reason}.`});
            alerts.push({recipientType: RESTAURANT, recipientId: e.restaurantId, channel: PUSH,
                message: string `Order ${id} was cancelled: ${reason}.`});
        }
    }
    return alerts;
}

// "Sending" is simulated: log it, store it, and announce it on notifications.sent.
isolated function send(string eventId, string orderId, string eventType, Alert a) returns error? {
    Notification n = {
        notificationId: string `${eventId}:${a.channel}:${a.recipientType}:${a.recipientId}`,
        orderId,
        eventType,
        recipientType: a.recipientType,
        recipientId: a.recipientId,
        channel: a.channel,
        message: a.message,
        status: "SENT",
        createdAt: nowIso()
    };
    error? stored = notifications->insertOne(n);
    if stored is error {
        if isDuplicateKey(stored) {
            return; // already sent for this event
        }
        return stored;
    }
    log:printInfo(string `[${a.channel} -> ${a.recipientType} ${a.recipientId}] ${a.message}`);
    check publish(TOPIC_NOTIFICATIONS_SENT, orderId, <NotificationSentEvent>{
        eventId: newEventId(), occurredAt: n.createdAt, notificationId: n.notificationId, orderId,
        recipientType: a.recipientType, recipientId: a.recipientId, channel: a.channel, message: a.message
    });
}

isolated function short(string orderId) returns string =>
    orderId.length() > 12 ? orderId.substring(0, 12) : orderId;
