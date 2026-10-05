import ballerina/constraint;

// OrderStatus, Address and OrderItem are part of the shared event contract
// and live in events.bal.

// One entry in the audit trail of an order.
public type StatusChange record {|
    OrderStatus status;
    string at;
    // Who caused the change, e.g. "customer", "restaurant", "payment-service"
    string triggeredBy;
    string? reason = ();
|};

// The order document stored in MongoDB (order_db.orders).
public type Order record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    decimal totalAmount;
    string currency;
    Address deliveryAddress;
    OrderStatus status;
    StatusChange[] statusHistory;
    string? paymentId = ();
    string? deliveryId = ();
    string? driverId = ();
    string createdAt;
    string updatedAt;
|};

// ---------- HTTP request / response payloads ----------

public type CreateOrderRequest record {|
    @constraint:String {minLength: 1}
    string customerId;
    @constraint:String {minLength: 1}
    string restaurantId;
    @constraint:Array {minLength: 1}
    OrderItem[] items;
    Address deliveryAddress;
|};

public type UpdateStatusRequest record {|
    OrderStatus status;
    string? reason = ();
|};

public type CancelOrderRequest record {|
    string? reason = ();
|};

public type ErrorBody record {|
    string message;
|};

// ---------- Domain errors (mapped to HTTP status codes in service.bal) ----------

public type OrderNotFoundError distinct error;

public type InvalidTransitionError distinct error;

public type ConcurrentUpdateError distinct error;
