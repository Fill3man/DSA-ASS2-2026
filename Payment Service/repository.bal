import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: mongoUri});
final mongodb:Collection payments = check getPayments();

isolated function getPayments() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("payments");
}

isolated function findPayment(map<json> filter) returns Payment?|error {
    return check payments->findOne(filter, {}, (), Payment);
}

isolated function listPayments(map<json> filter) returns Payment[]|error {
    stream<Payment, error?> result = check payments->find(filter, {sort: {createdAt: -1}, 'limit: 200}, (), Payment);
    return from Payment p in result select p;
}

isolated function insertPayment(Payment p) returns error? {
    check payments->insertOne(p);
}

// Moves a PENDING payment to its final state - unless the order was
// cancelled meanwhile, in which case nothing is modified and we return false.
isolated function finishPayment(string orderId, PaymentStatus status, string? reason) returns boolean|error {
    mongodb:UpdateResult r = check payments->updateOne(
        {orderId, status: PENDING, cancelRequested: false},
        {set: {status, failureReason: reason, updatedAt: nowIso()}, inc: {attempts: 1}}
    );
    return r.modifiedCount == 1;
}

isolated function setPaymentFields(map<json> filter, map<json> fields) returns boolean|error {
    fields["updatedAt"] = nowIso();
    mongodb:UpdateResult r = check payments->updateOne(filter, {set: fields});
    return r.modifiedCount == 1;
}
