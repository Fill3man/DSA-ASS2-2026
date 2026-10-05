public enum PaymentStatus {
    PENDING, COMPLETED, FAILED, REFUNDED
}

// Document in payment_db.payments. orderId is unique: one payment per order.
public type Payment record {|
    string paymentId;
    string orderId;
    decimal amount;
    string currency;
    string method;
    PaymentStatus status;
    int attempts;
    string? failureReason = ();
    // Set when the order is cancelled while the charge is still in flight.
    boolean cancelRequested = false;
    string createdAt;
    string updatedAt;
|};

public type ErrorBody record {|
    string message;
|};
