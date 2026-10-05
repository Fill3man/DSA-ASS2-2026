// Report rows produced by MongoDB aggregations over admin_db.order_facts.

public type Summary record {|
    int orders = 0;
    int delivered = 0;
    int cancelled = 0;
    int inProgress = 0;
    decimal revenue = 0;
    float cancellationRate = 0.0;
    float? avgEndToEndMinutes = ();
|};

public type RestaurantStats record {|
    string restaurantId;
    int orders;
    int delivered;
    int cancelled;
    decimal revenue;
    float? avgPrepMinutes = ();
    float cancellationRate = 0.0;
|};

public type DriverStats record {|
    string? driverId = ();
    int deliveries;
    float? avgDeliveryMinutes = ();
    float? avgEndToEndMinutes = ();
    float? fastestMinutes = ();
    float? slowestMinutes = ();
|};

public type DeliveryPerformance record {|
    int deliveries;
    float? avgDeliveryMinutes;
    float? avgEndToEndMinutes;
    DriverStats[] drivers;
|};

public type ErrorBody record {|
    string message;
|};
