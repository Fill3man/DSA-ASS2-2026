import ballerina/constraint;

public type GeoPoint record {|
    @constraint:Number {minValue: -90, maxValue: 90}
    float latitude;
    @constraint:Number {minValue: -180, maxValue: 180}
    float longitude;
|};

public enum DriverStatus {
    AVAILABLE, BUSY, OFFLINE
}

// Document in delivery_db.drivers.
public type Driver record {|
    string driverId;
    string name;
    string phone?;
    string vehicle?;
    DriverStatus status;
    GeoPoint location;
    string updatedAt?;
|};

public enum DeliveryStatus {
    PENDING_DRIVER, ASSIGNED, PICKED_UP, DELIVERED, FAILED
}

// Document in delivery_db.deliveries. Built up from several events, so most
// fields are optional until the matching event has arrived.
public type Delivery record {|
    string deliveryId;
    string orderId;
    DeliveryStatus status;
    string restaurantId?;
    string restaurantName?;
    string customerId?;
    string driverId?;
    GeoPoint pickup?;
    GeoPoint dropoff?;
    string dropoffAddress?;
    // Latest order status seen on orders.status-changed (pickup needs READY).
    string orderStatus?;
    int? etaMinutes = ();
    string? failureReason = ();
    string createdAt?;
    string assignedAt?;
    string pickedUpAt?;
    string deliveredAt?;
|};

// ---------- request payloads ----------

public type NewDriver record {|
    @constraint:String {minLength: 1}
    string name;
    string phone?;
    string vehicle = "Motorbike";
    GeoPoint location;
|};

public type DriverStatusChange record {|
    DriverStatus status;
|};

public type ErrorBody record {|
    string message;
|};

public type NotFoundError distinct error;

public type ConflictError distinct error;
