import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection restaurants = check collection("restaurants");
final mongodb:Collection menuItems = check collection("menu_items");
final mongodb:Collection reservations = check initReservations();

isolated function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection(name);
}

// reservations isn't in init-mongo.js, so the service makes sure its unique
// index exists (createIndex is a no-op if it already does).
isolated function initReservations() returns mongodb:Collection|error {
    mongodb:Collection c = check collection("reservations");
    check c->createIndex({orderId: 1}, {unique: true});
    return c;
}

// ---------- restaurants ----------

isolated function findRestaurant(string restaurantId) returns Restaurant|error {
    Restaurant? r = check restaurants->findOne({restaurantId}, {}, (), Restaurant);
    if r is () {
        return error NotFoundError(string `restaurant ${restaurantId} not found`);
    }
    return r;
}

isolated function listRestaurants(string? cuisine) returns Restaurant[]|error {
    map<json> filter = cuisine is string ? {cuisine} : {};
    stream<Restaurant, error?> result = check restaurants->find(filter, {sort: {name: 1}}, (), Restaurant);
    return from Restaurant r in result select r;
}

isolated function insertRestaurant(Restaurant r) returns error? {
    check restaurants->insertOne(r);
}

isolated function setOpeningHours(string restaurantId, OpeningHours[] hours) returns boolean|error {
    mongodb:UpdateResult r = check restaurants->updateOne({restaurantId}, {set: {openingHours: hours.toJson()}});
    return r.matchedCount == 1;
}

// ---------- menu ----------

isolated function listMenu(string restaurantId, boolean availableOnly) returns MenuItem[]|error {
    map<json> filter = {restaurantId};
    if availableOnly {
        filter["available"] = true;
    }
    stream<MenuItem, error?> result = check menuItems->find(filter, {sort: {category: 1, name: 1}}, (), MenuItem);
    return from MenuItem m in result select m;
}

isolated function findMenuItem(string restaurantId, string itemId) returns MenuItem|error {
    MenuItem? m = check menuItems->findOne({restaurantId, itemId}, {}, (), MenuItem);
    if m is () {
        return error NotFoundError(string `menu item ${itemId} not found at ${restaurantId}`);
    }
    return m;
}

isolated function insertMenuItem(MenuItem m) returns error? {
    check menuItems->insertOne(m);
}

isolated function updateMenuItem(string restaurantId, string itemId, mongodb:Update update)
        returns boolean|error {
    mongodb:UpdateResult r = check menuItems->updateOne({restaurantId, itemId}, update);
    return r.matchedCount == 1;
}

// Atomically takes `quantity` units, but only if the item is available and
// enough stock remains. Two orders racing for the last portion can't both
// succeed: the filter and the decrement are one operation in MongoDB.
isolated function takeStock(string restaurantId, string itemId, int quantity) returns boolean|error {
    mongodb:UpdateResult r = check menuItems->updateOne(
        {restaurantId, itemId, available: true, stock: {"$gte": quantity}},
        {inc: {stock: -quantity}}
    );
    return r.modifiedCount == 1;
}

isolated function returnStock(string restaurantId, string itemId, int quantity) returns error? {
    _ = check menuItems->updateOne({restaurantId, itemId}, {inc: {stock: quantity}});
}

// ---------- reservations ----------

isolated function findReservation(string orderId) returns Reservation?|error {
    return check reservations->findOne({orderId}, {}, (), Reservation);
}

isolated function insertReservation(Reservation r) returns error? {
    check reservations->insertOne(r);
}

// Compare-and-set RESERVED -> RELEASED; true only for the caller that won.
isolated function releaseReservation(string orderId) returns boolean|error {
    mongodb:UpdateResult r = check reservations->updateOne({orderId, status: RESERVED}, {set: {status: RELEASED}});
    return r.modifiedCount == 1;
}
