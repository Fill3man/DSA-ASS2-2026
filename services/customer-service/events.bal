// Event contract shared by all services. Every service keeps a copy of this
// file; docs/EVENTS.md is the source of truth. If you change a payload here,
// change it in docs/EVENTS.md and tell the teams that consume that topic.
//
// Keys: every order-scoped event is published with key = orderId so that all
// events for one order land on the same partition and are consumed in order.

import ballerina/constraint;

// ---------- Types used inside event payloads ----------

// Lifecycle states of an order. order-service/state_machine.bal holds the allowed transitions.
public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

public type Address record {|
    string street;
    string city;
    string? postalCode = ();
    float? latitude = ();
    float? longitude = ();
|};

public type OrderItem record {|
    @constraint:String {minLength: 1}
    string itemId;
    @constraint:String {minLength: 1}
    string name;
    @constraint:Int {minValue: 1}
    int quantity;
    @constraint:Number {minValue: 0}
    decimal unitPrice;
|};

// ---------- Topic names ----------
public const TOPIC_ORDERS_CREATED = "orders.created";
public const TOPIC_ORDERS_STATUS_CHANGED = "orders.status-changed";
public const TOPIC_ORDERS_CANCELLED = "orders.cancelled";
public const TOPIC_PAYMENTS_COMPLETED = "payments.completed";
public const TOPIC_PAYMENTS_FAILED = "payments.failed";
public const TOPIC_RESTAURANTS_ORDER_REJECTED = "restaurants.order-rejected";
public const TOPIC_RESTAURANTS_ORDER_ACCEPTED = "restaurants.order-accepted";
public const TOPIC_NOTIFICATIONS_SENT = "notifications.sent";
public const TOPIC_DELIVERY_ASSIGNED = "delivery.assigned";
public const TOPIC_DELIVERY_PICKED_UP = "delivery.picked-up";
public const TOPIC_DELIVERY_COMPLETED = "delivery.completed";
public const TOPIC_DELIVERY_LOCATION_UPDATED = "delivery.location-updated";
public const TOPIC_ORDERS_DLQ = "orders.dlq";

// ---------- Published by order-service ----------

public type OrderCreatedEvent record {
    string eventId;
    string eventType = "OrderCreated";
    string occurredAt;
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    decimal totalAmount;
    string currency;
    Address deliveryAddress;
};

public type OrderStatusChangedEvent record {
    string eventId;
    string eventType = "OrderStatusChanged";
    string occurredAt;
    string orderId;
    string customerId;
    string restaurantId;
    string? driverId = ();
    OrderStatus fromStatus;
    OrderStatus toStatus;
    string triggeredBy;
    string? reason = ();
};

public type OrderCancelledEvent record {
    string eventId;
    string eventType = "OrderCancelled";
    string occurredAt;
    string orderId;
    string customerId;
    string restaurantId;
    string? paymentId = ();
    decimal totalAmount;
    string? reason = ();
};

// ---------- Published by payment-service ----------

public type PaymentCompletedEvent record {
    string eventId;
    string eventType = "PaymentCompleted";
    string occurredAt;
    string orderId;
    string paymentId;
    decimal amount;
    string method;
};

public type PaymentFailedEvent record {
    string eventId;
    string eventType = "PaymentFailed";
    string occurredAt;
    string orderId;
    string paymentId;
    string reason;
};

// ---------- Published by restaurant-service ----------

public type OrderRejectedEvent record {
    string eventId;
    string eventType = "OrderRejected";
    string occurredAt;
    string orderId;
    string restaurantId;
    string reason;
};

// Stock has been reserved; carries the pickup point so delivery-service can
// choose the nearest driver without calling restaurant-service.
public type OrderAcceptedEvent record {
    string eventId;
    string eventType = "OrderAccepted";
    string occurredAt;
    string orderId;
    string restaurantId;
    string restaurantName;
    float pickupLatitude;
    float pickupLongitude;
};

// ---------- Published by notification-service ----------

public type NotificationSentEvent record {
    string eventId;
    string eventType = "NotificationSent";
    string occurredAt;
    string notificationId;
    string? orderId = ();
    string recipientType;
    string recipientId;
    string channel;
    string message;
};

// ---------- Published by delivery-service ----------

public type DeliveryAssignedEvent record {
    string eventId;
    string eventType = "DeliveryAssigned";
    string occurredAt;
    string orderId;
    string deliveryId;
    string driverId;
    int? etaMinutes = ();
};

public type DeliveryPickedUpEvent record {
    string eventId;
    string eventType = "DeliveryPickedUp";
    string occurredAt;
    string orderId;
    string deliveryId;
    string driverId;
};

public type DeliveryCompletedEvent record {
    string eventId;
    string eventType = "DeliveryCompleted";
    string occurredAt;
    string orderId;
    string deliveryId;
    string driverId;
};

// Keyed by driverId (not orderId) - high volume, consumed by the map UI.
public type DriverLocationUpdatedEvent record {
    string eventId;
    string eventType = "DriverLocationUpdated";
    string occurredAt;
    string driverId;
    string? orderId = ();
    float latitude;
    float longitude;
};

// Wrapper written to orders.dlq when an incoming event cannot be processed.
public type DeadLetter record {|
    string failedAt;
    string sourceTopic;
    int sourcePartition;
    int sourceOffset;
    string errorMessage;
    string rawValue;
|};
