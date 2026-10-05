public enum RecipientType {
    CUSTOMER, RESTAURANT, DRIVER
}

// IN_APP notifications are shown in the web UI's bell; the others are
// simulated external channels (logged, not really sent).
public enum Channel {
    EMAIL, SMS, PUSH, IN_APP
}

// Document in notification_db.notifications.
public type Notification record {|
    // eventId + channel + recipient, so a redelivered event can't notify
    // twice (unique index on notificationId).
    string notificationId;
    string? orderId = ();
    string eventType;
    RecipientType recipientType;
    string recipientId;
    Channel channel;
    string message;
    string status;
    boolean read = false;
    string createdAt;
|};

// What an event turns into, before it is stored and "sent".
type Alert record {|
    RecipientType recipientType;
    string recipientId;
    Channel channel;
    string message;
|};

public type Recipient record {|
    RecipientType recipientType;
    string recipientId;
|};
