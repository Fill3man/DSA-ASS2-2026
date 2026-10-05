import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;

// Kafka plumbing shared by every service except order-service (which has its
// own, more detailed version in producer.bal / consumer.bal). Each service
// defines SERVICE_NAME in config.bal and handleEvent() in consumer.bal.
// Keep this file identical across services: scripts/templates/messaging.bal.

// acks=all + idempotence: a send is acknowledged only once durable, and
// retries never duplicate a message.
final kafka:Producer producer = check new (kafkaBootstrap, {
    clientId: SERVICE_NAME,
    acks: kafka:ACKS_ALL,
    enableIdempotence: true,
    retryCount: 5
});

isolated function newEventId() returns string => uuid:createType4AsString();

isolated function nowIso() returns string => time:utcToString(time:utcNow());

// Publishes `event` as JSON. Use orderId as the key for order-scoped events so
// they keep their order on one partition.
isolated function publish(string topic, string key, anydata event) returns error? {
    check producer->send({topic, key: key.toBytes(), value: event.toJsonString().toBytes()});
}

// Handles one record: parse, call handleEvent with retries, dead-letter on failure.
// Never returns an error, so one bad event can't block the partition.
isolated function processRecord(kafka:BytesConsumerRecord rec) {
    string topic = rec.offset.partition.topic;
    string|error raw = string:fromBytes(rec.value);
    json|error payload = raw is string ? raw.fromJsonString() : raw;
    if payload is error {
        deadLetter(rec, raw is string ? raw : "<non-utf8>", payload);
        return;
    }
    error? lastError = ();
    foreach int attempt in 1 ... 3 {
        lastError = handleEvent(topic, payload);
        if lastError is () {
            return;
        }
        log:printWarn("event handling failed, retrying", topic = topic, attempt = attempt,
                reason = lastError.message());
        runtime:sleep(<decimal>attempt * 0.5);
    }
    deadLetter(rec, payload.toJsonString(), <error>lastError);
}

isolated function deadLetter(kafka:BytesConsumerRecord rec, string rawValue, error cause) {
    log:printError("sending event to dead-letter topic", cause, topic = rec.offset.partition.topic,
            offset = rec.offset.offset);
    DeadLetter letter = {
        failedAt: nowIso(),
        sourceTopic: rec.offset.partition.topic,
        sourcePartition: rec.offset.partition.partition,
        sourceOffset: rec.offset.offset,
        errorMessage: SERVICE_NAME + ": " + cause.message(),
        rawValue
    };
    error? sent = publish(TOPIC_ORDERS_DLQ, letter.sourceTopic, letter);
    if sent is error {
        log:printError("could not write to dead-letter topic", sent);
    }
}

// Commits after the whole batch has been processed (at-least-once delivery).
isolated function commitBatch(kafka:Caller caller) {
    kafka:Error? result = caller->commit();
    if result is kafka:Error {
        log:printError("failed to commit offsets", result);
    }
}

isolated function isDuplicateKey(error e) returns boolean => e.message().includes("E11000");
