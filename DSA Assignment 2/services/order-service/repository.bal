import ballerinax/mongodb;

// Persistence for order_db.orders. Collection validators and indexes are
// created by infra/mongo/init-mongo.js when the Mongo container first starts.

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection orders = check getOrdersCollection();

isolated function getOrdersCollection() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("orders");
}

isolated function insertOrder(Order 'order) returns error? {
    check orders->insertOne('order);
}

isolated function findOrder(string orderId) returns Order|OrderNotFoundError|error {
    Order? found = check orders->findOne({orderId}, {}, (), Order);
    if found is () {
        return error OrderNotFoundError(string `order ${orderId} not found`);
    }
    return found;
}

isolated function findOrders(map<json> filter, int 'limit) returns Order[]|error {
    stream<Order, error?> result = check orders->find(filter, {sort: {createdAt: -1}, 'limit: 'limit}, (), Order);
    return from Order o in result select o;
}

// Compare-and-set update: only succeeds if the order is still in `expected`.
// Two consumers (or a consumer and an HTTP call) racing on the same order
// cannot both win, which keeps the state machine consistent under load.
// Returns false if the status had already changed underneath us.
isolated function updateStatusIfCurrent(string orderId, OrderStatus expected, StatusChange change,
        map<json> extraFields) returns boolean|error {
    map<json> setFields = {...extraFields};
    setFields["status"] = change.status;
    setFields["updatedAt"] = change.at;
    mongodb:UpdateResult result = check orders->updateOne(
        {orderId, status: expected},
        {set: setFields, "push": {statusHistory: change.toJson()}}
    );
    return result.modifiedCount == 1;
}

// Sets fields that do not change the status (e.g. driverId once a driver is assigned).
isolated function setOrderFields(string orderId, map<json> fields) returns boolean|error {
    mongodb:UpdateResult result = check orders->updateOne({orderId}, {set: fields});
    return result.matchedCount == 1;
}
