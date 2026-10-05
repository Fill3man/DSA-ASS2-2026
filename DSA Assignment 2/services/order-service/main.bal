import ballerina/http;
import ballerina/log;

type OrderCreated record {|
    *http:Created;
    Order body;
|};

type OrderResponse Order|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError;

@http:ServiceConfig {
    cors: {allowOrigins: ["*"]}
}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: "order-service"};
    }

    // Customer places an order. Status starts at CREATED and `orders.created`
    // is published; payment-service picks it up from there.
    resource function post orders(CreateOrderRequest req) returns OrderCreated|http:InternalServerError {
        Order|error created = createOrder(req);
        if created is error {
            return internalError(created);
        }
        return <OrderCreated>{
            headers: {"Location": "/api/v1/orders/" + created.orderId},
            body: created
        };
    }

    resource function get orders(string? customerId = (), string? restaurantId = (), OrderStatus? status = (),
            int 'limit = 50) returns Order[]|http:BadRequest|http:InternalServerError {
        if 'limit < 1 || 'limit > 500 {
            return <http:BadRequest>{body: <ErrorBody>{message: "limit must be between 1 and 500"}};
        }
        map<json> filter = {};
        if customerId is string {
            filter["customerId"] = customerId;
        }
        if restaurantId is string {
            filter["restaurantId"] = restaurantId;
        }
        if status is OrderStatus {
            filter["status"] = status;
        }
        Order[]|error result = findOrders(filter, 'limit);
        return result is error ? internalError(result) : result;
    }

    resource function get orders/[string orderId]() returns OrderResponse {
        return toResponse(findOrder(orderId));
    }

    resource function get orders/[string orderId]/history() returns StatusChange[]|http:NotFound|http:InternalServerError {
        Order|error found = findOrder(orderId);
        if found is OrderNotFoundError {
            return <http:NotFound>{body: <ErrorBody>{message: found.message()}};
        }
        if found is error {
            return internalError(found);
        }
        return found.statusHistory;
    }

    // Restaurant moves the order through the kitchen: PREPARING, READY,
    // or CANCELLED (e.g. an item ran out). Event-driven statuses are refused here.
    resource function patch orders/[string orderId]/status(UpdateStatusRequest req) returns OrderResponse {
        if restaurantSettableStatuses.indexOf(req.status) is () {
            return <http:BadRequest>{
                body: <ErrorBody>{
                    message: string `${req.status} is set by events, not by this endpoint; allowed: ${restaurantSettableStatuses.toString()}`
                }
            };
        }
        return toResponse(transitionOrder(orderId, req.status, "restaurant", req.reason));
    }

    // Customer cancels. Only allowed before the kitchen starts.
    resource function post orders/[string orderId]/cancel(CancelOrderRequest? req) returns OrderResponse {
        Order|error current = findOrder(orderId);
        if current is error {
            return toResponse(current);
        }
        if customerCancellableStatuses.indexOf(current.status) is () {
            return <http:Conflict>{
                body: <ErrorBody>{message: string `order is ${current.status}; customers can only cancel before preparation starts`}
            };
        }
        return toResponse(transitionOrder(orderId, CANCELLED, "customer", req?.reason ?: "cancelled by customer"));
    }
}

isolated function toResponse(Order|error result) returns OrderResponse {
    if result is OrderNotFoundError {
        return <http:NotFound>{body: <ErrorBody>{message: result.message()}};
    }
    if result is InvalidTransitionError|ConcurrentUpdateError {
        return <http:Conflict>{body: <ErrorBody>{message: result.message()}};
    }
    if result is error {
        return internalError(result);
    }
    return result;
}

isolated function internalError(error err) returns http:InternalServerError {
    log:printError("request failed", err);
    return {body: <ErrorBody>{message: "internal error"}};
}
