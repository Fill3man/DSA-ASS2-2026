import ballerina/http;
import ballerina/log;

// Payment Service - simulates charging the customer and emits the result.
// The work happens in consumer.bal; the HTTP API is read-only.

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    resource function get payments/[string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        Payment?|error p = findPayment({paymentId});
        if p is error {
            return internalError(p);
        }
        return p ?: <http:NotFound>{body: <ErrorBody>{message: string `payment ${paymentId} not found`}};
    }

    resource function get payments(string? orderId = (), PaymentStatus? status = ())
            returns Payment[]|http:InternalServerError {
        map<json> filter = {};
        if orderId is string {
            filter["orderId"] = orderId;
        }
        if status is PaymentStatus {
            filter["status"] = status;
        }
        Payment[]|error result = listPayments(filter);
        return result is error ? internalError(result) : result;
    }
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("request failed", e);
    return {body: <ErrorBody>{message: "internal error"}};
}
