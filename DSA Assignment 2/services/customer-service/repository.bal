import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection customers = check collection("customers");
final mongodb:Collection orderHistory = check collection("order_history");

isolated function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection(name);
}

isolated function findCustomer(string customerId) returns Customer|error {
    Customer? found = check customers->findOne({customerId}, {}, (), Customer);
    if found is () {
        return error CustomerNotFoundError(string `customer ${customerId} not found`);
    }
    return found;
}

isolated function listCustomers() returns Customer[]|error {
    stream<Customer, error?> result = check customers->find({}, {sort: {name: 1}}, (), Customer);
    return from Customer c in result select c;
}

isolated function emailTaken(string email) returns boolean|error {
    int count = check customers->countDocuments({email});
    return count > 0;
}

isolated function insertCustomer(Customer c) returns error? {
    check customers->insertOne(c);
}

isolated function updateCustomer(string customerId, map<json> fields) returns boolean|error {
    mongodb:UpdateResult r = check customers->updateOne({customerId}, {set: fields});
    return r.matchedCount == 1;
}

isolated function addAddress(string customerId, CustomerAddress address) returns boolean|error {
    if address.isDefault {
        // Only one default: clear the flag on every existing address first.
        _ = check customers->updateOne({customerId}, {set: {"addresses.$[].isDefault": false}});
    }
    mongodb:UpdateResult r = check customers->updateOne({customerId}, {"push": {addresses: address.toJson()}});
    return r.matchedCount == 1;
}

isolated function removeAddress(string customerId, string addressId) returns boolean|error {
    mongodb:UpdateResult r = check customers->updateOne({customerId}, {"pull": {addresses: {addressId}}});
    return r.modifiedCount == 1;
}

isolated function customerOrders(string customerId, int 'limit) returns OrderHistoryEntry[]|error {
    stream<OrderHistoryEntry, error?> result = check orderHistory->find({customerId},
            {sort: {updatedAt: -1}, 'limit: 'limit}, (), OrderHistoryEntry);
    return from OrderHistoryEntry e in result select e;
}

// Upsert so events can arrive in either order: if status-changed comes
// first the row is created then, and orders.created only fills in details
// (setOnInsert means it never overwrites a newer status).
isolated function recordOrderCreated(OrderCreatedEvent e) returns error? {
    _ = check orderHistory->updateOne({orderId: e.orderId}, {
        set: {customerId: e.customerId, restaurantId: e.restaurantId, totalAmount: e.totalAmount, createdAt: e.occurredAt},
        setOnInsert: {status: CREATED, updatedAt: e.occurredAt}
    }, {upsert: true});
}

isolated function recordStatusChange(OrderStatusChangedEvent e) returns error? {
    _ = check orderHistory->updateOne({orderId: e.orderId}, {
        set: {customerId: e.customerId, restaurantId: e.restaurantId, status: e.toStatus, updatedAt: e.occurredAt}
    }, {upsert: true});
}
