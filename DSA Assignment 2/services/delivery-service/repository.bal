import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection drivers = check collection("drivers");
final mongodb:Collection deliveries = check collection("deliveries");

isolated function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection(name);
}

// ---------- drivers ----------

isolated function findDriver(string driverId) returns Driver|error {
    Driver? d = check drivers->findOne({driverId}, {}, (), Driver);
    if d is () {
        return error NotFoundError(string `driver ${driverId} not found`);
    }
    return d;
}

isolated function listDrivers(map<json> filter) returns Driver[]|error {
    stream<Driver, error?> result = check drivers->find(filter, {sort: {name: 1}}, (), Driver);
    return from Driver d in result select d;
}

isolated function insertDriver(Driver d) returns error? {
    check drivers->insertOne(d);
}

// Compare-and-set on the driver's status. Claiming an AVAILABLE driver this
// way means two deliveries can never grab the same driver.
isolated function setDriverStatusIf(string driverId, DriverStatus expected, DriverStatus next) returns boolean|error {
    mongodb:UpdateResult r = check drivers->updateOne({driverId, status: expected},
            {set: {status: next, updatedAt: nowIso()}});
    return r.modifiedCount == 1;
}

isolated function setDriverLocation(string driverId, GeoPoint location) returns boolean|error {
    mongodb:UpdateResult r = check drivers->updateOne({driverId}, {set: {location: location.toJson(), updatedAt: nowIso()}});
    return r.matchedCount == 1;
}

// ---------- deliveries ----------

isolated function findDelivery(map<json> filter) returns Delivery|error {
    Delivery? d = check deliveries->findOne(filter, {}, (), Delivery);
    if d is () {
        return error NotFoundError(string `delivery not found for ${filter.toJsonString()}`);
    }
    return d;
}

isolated function listDeliveries(map<json> filter) returns Delivery[]|error {
    stream<Delivery, error?> result = check deliveries->find(filter, {sort: {createdAt: -1}, 'limit: 200}, (), Delivery);
    return from Delivery d in result select d;
}

// One delivery document per order, created by whichever event arrives first.
isolated function upsertDelivery(string orderId, map<json> fields) returns error? {
    _ = check deliveries->updateOne({orderId}, {
        set: fields,
        setOnInsert: {deliveryId: deliveryIdFor(orderId), status: PENDING_DRIVER, createdAt: nowIso()}
    }, {upsert: true});
}

// Derived from the orderId, so the same order always maps to the same delivery.
isolated function deliveryIdFor(string orderId) returns string =>
    "del-" + (orderId.startsWith("ord-") ? orderId.substring(4) : orderId);

// Compare-and-set on the delivery status.
isolated function updateDeliveryIf(string orderId, DeliveryStatus expected, map<json> fields) returns boolean|error {
    mongodb:UpdateResult r = check deliveries->updateOne({orderId, status: expected}, {set: fields});
    return r.modifiedCount == 1;
}
