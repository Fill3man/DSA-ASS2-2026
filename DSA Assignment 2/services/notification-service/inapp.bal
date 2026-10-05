import ballerina/log;
import ballerinax/mongodb;

// In-app notifications: every party to an order (customer, restaurant and,
// once assigned, the driver) gets an IN_APP message on every status change,
// worded for their role. The web UI shows them in the bell menu.

final mongodb:Collection orderParties = check getOrderParties();

isolated function getOrderParties() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    mongodb:Collection c = check db->getCollection("order_parties");
    check c->createIndex({orderId: 1}, {unique: true});
    return c;
}

// Who is involved in each order. status-changed events only carry driverId
// after order-service has recorded it, so delivery.assigned stores it here too.
type OrderParties record {|
    string orderId;
    string customerId?;
    string restaurantId?;
    string driverId?;
|};

isolated function rememberParties(string orderId, map<json> fields) returns error? {
    _ = check orderParties->updateOne({orderId}, {set: fields}, {upsert: true});
}

isolated function partiesOf(string orderId) returns OrderParties|error {
    OrderParties? p = check orderParties->findOne({orderId}, {}, (), OrderParties);
    return p ?: {orderId};
}

isolated function inApp(RecipientType 'type, string id, string message) returns Alert =>
    {recipientType: 'type, recipientId: id, channel: IN_APP, message};

isolated function inAppForCreated(OrderCreatedEvent e) returns Alert[] {
    // Best effort: status-changed events carry these ids as well.
    error? saved = rememberParties(e.orderId, {customerId: e.customerId, restaurantId: e.restaurantId});
    if saved is error {
        log:printWarn("could not record order parties", orderId = e.orderId, reason = saved.message());
    }
    string id = short(e.orderId);
    return [
        inApp(CUSTOMER, e.customerId, string `🧾 Order ${id} placed - ${e.currency} ${e.totalAmount.round(2)}. Waiting for payment.`),
        inApp(RESTAURANT, e.restaurantId, string `🆕 New order ${id} received (${e.currency} ${e.totalAmount.round(2)}).`)
    ];
}

isolated function inAppForAssigned(DeliveryAssignedEvent e) returns Alert[]|error {
    check rememberParties(e.orderId, {driverId: e.driverId});
    OrderParties p = check partiesOf(e.orderId);
    string id = short(e.orderId);
    Alert[] alerts = [inApp(DRIVER, e.driverId, string `🛵 You've been assigned order ${id}. Head to the restaurant.`)];
    string? customerId = p?.customerId;
    if customerId is string {
        alerts.push(inApp(CUSTOMER, customerId, string `🛵 A driver has been assigned to order ${id} (about ${e.etaMinutes ?: 0} min).`));
    }
    string? restaurantId = p?.restaurantId;
    if restaurantId is string {
        alerts.push(inApp(RESTAURANT, restaurantId, string `🛵 A driver is on the way for order ${id}.`));
    }
    return alerts;
}

isolated function inAppForStatus(OrderStatusChangedEvent e) returns Alert[] {
    string id = short(e.orderId);
    string reason = e.reason ?: "no reason given";
    [string, string, string] [toCustomer, toRestaurant, toDriver] = messagesFor(e.toStatus, id, reason);

    Alert[] alerts = [inApp(CUSTOMER, e.customerId, toCustomer), inApp(RESTAURANT, e.restaurantId, toRestaurant)];
    string? driverId = e.driverId;
    if driverId is () {
        OrderParties|error p = partiesOf(e.orderId);
        driverId = p is OrderParties ? p?.driverId : ();
    }
    if driverId is string {
        alerts.push(inApp(DRIVER, driverId, toDriver));
    }
    return alerts;
}

// Customer, restaurant and driver wording for each status.
isolated function messagesFor(OrderStatus status, string id, string reason) returns [string, string, string] {
    match status {
        CONFIRMED => {
            return [
            string `✅ Payment received - order ${id} is confirmed.`,
            string `✅ Order ${id} is paid. You can start preparing it.`,
            string `✅ Order ${id} is confirmed.`
        ];
        }
        PREPARING => {
            return [
            string `👩‍🍳 The kitchen is preparing order ${id}.`,
            string `👩‍🍳 Order ${id} marked as preparing.`,
            string `👩‍🍳 Order ${id} is being prepared.`
        ];
        }
        READY => {
            return [
            string `🔔 Order ${id} is ready and waiting for the driver.`,
            string `🔔 Order ${id} is ready for collection.`,
            string `🔔 Order ${id} is ready - go collect it!`
        ];
        }
        OUT_FOR_DELIVERY => {
            return [
            string `🚚 Order ${id} is on its way to you!`,
            string `🚚 Order ${id} has been collected by the driver.`,
            string `🚚 Order ${id} picked up - deliver it to the customer.`
        ];
        }
        DELIVERED => {
            return [
            string `🎉 Order ${id} delivered. Enjoy your meal!`,
            string `🎉 Order ${id} was delivered.`,
            string `🎉 Order ${id} delivered. Nice work!`
        ];
        }
        CANCELLED => {
            return [
            string `❌ Order ${id} was cancelled: ${reason}.`,
            string `❌ Order ${id} was cancelled: ${reason}.`,
            string `❌ Order ${id} was cancelled - no need to collect it.`
        ];
        }
        _ => {
            string s = string `Order ${id} is now ${status}.`;
            return [s, s, s];
        }
    }
}
