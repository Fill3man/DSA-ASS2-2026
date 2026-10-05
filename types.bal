import ballerina/constraint;

public type GeoPoint record {|
    float latitude;
    float longitude;
|};

public type RestaurantAddress record {|
    string street;
    string city;
    string? postalCode = ();
|};

public enum Day {
    MON, TUE, WED, THU, FRI, SAT, SUN
}

public type OpeningHours record {|
    Day day;
    @constraint:String {pattern: re `^([01][0-9]|2[0-3]):[0-5][0-9]$`}
    string open;
    @constraint:String {pattern: re `^([01][0-9]|2[0-3]):[0-5][0-9]$`}
    string close;
|};

// Document in restaurant_db.restaurants.
public type Restaurant record {|
    string restaurantId;
    string name;
    string cuisine?;
    RestaurantAddress address;
    GeoPoint location;
    OpeningHours[] openingHours;
|};

public type RestaurantView record {|
    *Restaurant;
    boolean openNow;
|};

// Document in restaurant_db.menu_items.
public type MenuItem record {|
    string itemId;
    string restaurantId;
    string name;
    string description?;
    string category?;
    decimal price;
    boolean available;
    int stock;
|};

public enum ReservationStatus {
    RESERVED, RELEASED, REJECTED
}

public type ReservedItem record {|
    string itemId;
    int quantity;
|};

// Document in restaurant_db.reservations: one per order, so stock is taken
// (and given back) exactly once even if Kafka redelivers an event.
public type Reservation record {|
    string orderId;
    string restaurantId;
    ReservedItem[] items;
    ReservationStatus status;
    string? reason = ();
    string createdAt;
|};

// ---------- request payloads ----------

public type NewRestaurant record {|
    @constraint:String {minLength: 1}
    string name;
    string cuisine?;
    RestaurantAddress address;
    GeoPoint location;
    OpeningHours[] openingHours = [];
|};

public type NewMenuItem record {|
    @constraint:String {minLength: 1}
    string name;
    string description?;
    string category?;
    @constraint:Number {minValue: 0}
    decimal price;
    boolean available = true;
    @constraint:Int {minValue: 0}
    int stock = 0;
|};

public type MenuItemUpdate record {|
    string name?;
    string description?;
    string category?;
    @constraint:Number {minValue: 0}
    decimal price?;
    boolean available?;
|};

// Either `delta` (relative, e.g. -3) or `set` (absolute).
public type StockChange record {|
    int delta?;
    @constraint:Int {minValue: 0}
    int set?;
|};

public type ErrorBody record {|
    string message;
|};

public type NotFoundError distinct error;
