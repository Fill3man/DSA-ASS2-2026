import ballerina/http;
import ballerina/log;

// Admin Service - reports on restaurant statistics and delivery performance.
// All figures come from admin_db.order_facts (see consumer.bal); admin never
// calls another service or reads another service's database.

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    // Platform totals. Optional ?from=2026-10-01&to=2026-10-05 (on order creation date).
    resource function get reports/summary(string? 'from = (), string? to = ()) returns Summary|http:InternalServerError {
        Summary|error s = summary('from, to);
        return s is error ? internalError(s) : s;
    }

    // One row per restaurant, highest revenue first. Revenue counts DELIVERED orders only.
    resource function get reports/restaurants(string? 'from = (), string? to = ())
            returns RestaurantStats[]|http:InternalServerError {
        RestaurantStats[]|error rows = restaurantStats(rangeFilter('from, to));
        return rows is error ? internalError(rows) : rows;
    }

    resource function get reports/restaurants/[string restaurantId]()
            returns RestaurantStats|http:NotFound|http:InternalServerError {
        RestaurantStats[]|error rows = restaurantStats({restaurantId});
        if rows is error {
            return internalError(rows);
        }
        if rows.length() == 0 {
            return <http:NotFound>{body: <ErrorBody>{message: string `no orders yet for ${restaurantId}`}};
        }
        return rows[0];
    }

    // Pickup-to-door and order-to-door times, overall and per driver.
    resource function get reports/delivery\-performance(string? 'from = (), string? to = ())
            returns DeliveryPerformance|http:InternalServerError {
        DeliveryPerformance|error p = deliveryPerformance('from, to);
        return p is error ? internalError(p) : p;
    }
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("report failed", e);
    return {body: <ErrorBody>{message: "internal error"}};
}
