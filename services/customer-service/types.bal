import ballerina/constraint;

public type CustomerAddress record {|
    string addressId;
    string label;
    string street;
    string city;
    string? postalCode = ();
    float? latitude = ();
    float? longitude = ();
    boolean isDefault = false;
|};

// Document in customer_db.customers.
public type Customer record {|
    string customerId;
    string name;
    string email;
    string? phone = ();
    CustomerAddress[] addresses;
    string createdAt;
|};

// Document in customer_db.order_history - a read model fed by order events.
public type OrderHistoryEntry record {|
    string orderId;
    string customerId;
    string restaurantId?;
    string status;
    decimal totalAmount?;
    string createdAt?;
    string updatedAt;
|};

// ---------- request payloads ----------

public type NewAddress record {|
    @constraint:String {minLength: 1}
    string label;
    @constraint:String {minLength: 1}
    string street;
    @constraint:String {minLength: 1}
    string city;
    string? postalCode = ();
    float? latitude = ();
    float? longitude = ();
    boolean isDefault = false;
|};

public type NewCustomer record {|
    @constraint:String {minLength: 1, maxLength: 100}
    string name;
    @constraint:String {pattern: re `^[^@\s]+@[^@\s]+\.[^@\s]+$`}
    string email;
    string? phone = ();
    NewAddress[] addresses = [];
|};

public type CustomerUpdate record {|
    @constraint:String {minLength: 1, maxLength: 100}
    string name?;
    string phone?;
|};

public type ErrorBody record {|
    string message;
|};

public type CustomerNotFoundError distinct error;
