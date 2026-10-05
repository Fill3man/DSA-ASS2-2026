import ballerina/lang.runtime;
import ballerina/log;
import ballerina/random;
import ballerina/uuid;
import ballerinax/kafka;

// Fraction of payments the simulated gateway randomly declines (0.0 - 1.0).
configurable float failureRate = 0.0;
// Orders above this amount are always declined ("card limit exceeded") -
// a deterministic way to demo the failure path.
configurable decimal cardLimit = 2000;
// Simulated gateway latency, in seconds.
configurable decimal minLatency = 0.5;
configurable decimal maxLatency = 1.5;

listener kafka:Listener eventListener = new (kafkaBootstrap, {
    groupId: SERVICE_NAME,
    clientId: SERVICE_NAME + "-consumer",
    topics: [TOPIC_ORDERS_CREATED, TOPIC_ORDERS_CANCELLED],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false,
    pollingInterval: 1
});

service on eventListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) {
        foreach kafka:BytesConsumerRecord rec in records {
            processRecord(rec);
        }
        commitBatch(caller);
    }
}

isolated function handleEvent(string topic, json payload) returns error? {
    if topic == TOPIC_ORDERS_CREATED {
        OrderCreatedEvent e = check payload.cloneWithType();
        check chargeOrder(e);
    } else if topic == TOPIC_ORDERS_CANCELLED {
        OrderCancelledEvent e = check payload.cloneWithType();
        check cancelPayment(e);
    }
}

isolated function chargeOrder(OrderCreatedEvent e) returns error? {
    Payment? existing = check findPayment({orderId: e.orderId});
    if existing is Payment && existing.status != PENDING {
        return; // already charged or declined - redelivered event
    }
    if existing is () {
        string now = nowIso();
        Payment p = {
            paymentId: "pay-" + uuid:createType4AsString().substring(0, 8),
            orderId: e.orderId,
            amount: e.totalAmount,
            currency: e.currency,
            method: "CARD",
            status: PENDING,
            attempts: 0,
            createdAt: now,
            updatedAt: now
        };
        error? inserted = insertPayment(p);
        if inserted is error {
            // Unique index on orderId: another replica got here first.
            return isDuplicateKey(inserted) ? () : inserted;
        }
    }
    Payment payment = <Payment>check findPayment({orderId: e.orderId});

    // ---- simulated payment gateway ----
    float jitter = random:createDecimal();
    runtime:sleep(minLatency + (maxLatency - minLatency) * <decimal>jitter);
    string? declineReason = ();
    if e.totalAmount > cardLimit {
        declineReason = string `card limit of ${cardLimit} exceeded`;
    } else if random:createDecimal() < failureRate {
        declineReason = "card declined by issuer";
    }

    PaymentStatus outcome = declineReason is () ? COMPLETED : FAILED;
    if !check finishPayment(e.orderId, outcome, declineReason) {
        // Order was cancelled while we were "talking to the bank".
        _ = check setPaymentFields({orderId: e.orderId, status: PENDING},
                {status: FAILED, failureReason: "order cancelled before payment completed"});
        log:printInfo("payment abandoned, order already cancelled", orderId = e.orderId);
        return;
    }

    if declineReason is () {
        check publish(TOPIC_PAYMENTS_COMPLETED, e.orderId, <PaymentCompletedEvent>{
            eventId: newEventId(), occurredAt: nowIso(), orderId: e.orderId,
            paymentId: payment.paymentId, amount: e.totalAmount, method: payment.method
        });
        log:printInfo("payment completed", orderId = e.orderId, amount = e.totalAmount);
    } else {
        check publish(TOPIC_PAYMENTS_FAILED, e.orderId, <PaymentFailedEvent>{
            eventId: newEventId(), occurredAt: nowIso(), orderId: e.orderId,
            paymentId: payment.paymentId, reason: declineReason
        });
        log:printWarn("payment declined", orderId = e.orderId, reason = declineReason);
    }
}

isolated function cancelPayment(OrderCancelledEvent e) returns error? {
    Payment? p = check findPayment({orderId: e.orderId});
    if p is () {
        // Cancelled before we even saw orders.created: leave a FAILED record
        // so the late orders.created is recognised as already handled.
        string now = nowIso();
        error? inserted = insertPayment({
            paymentId: "pay-" + uuid:createType4AsString().substring(0, 8),
            orderId: e.orderId, amount: e.totalAmount, currency: "NAD", method: "CARD",
            status: FAILED, attempts: 0, failureReason: "order cancelled before payment",
            createdAt: now, updatedAt: now
        });
        return inserted is error && !isDuplicateKey(inserted) ? inserted : ();
    }
    if p.status == PENDING {
        _ = check setPaymentFields({orderId: e.orderId, status: PENDING}, {cancelRequested: true});
    } else if p.status == COMPLETED {
        if check setPaymentFields({orderId: e.orderId, status: COMPLETED}, {status: REFUNDED}) {
            log:printInfo("payment refunded", orderId = e.orderId, amount = p.amount);
        }
    }
}
