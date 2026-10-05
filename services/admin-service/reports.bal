// Reports as MongoDB aggregation pipelines over order_facts. The database
// does the grouping and maths; Ballerina only adds derived ratios.

const DELIVERED_S = "DELIVERED";
const CANCELLED_S = "CANCELLED";

isolated function countIf(string status) returns map<json> =>
    {"$sum": {"$cond": [{"$eq": ["$status", status]}, 1, 0]}};

isolated function minutes(string msField) returns map<json> =>
    {"$round": [{"$divide": [msField, 60000]}, 1]};

// Difference a - b in ms, or null unless both fields exist.
isolated function msBetween(string a, string b) returns map<json> => {
    "$cond": [{"$and": [{"$gt": ["$" + a, null]}, {"$gt": ["$" + b, null]}]},
        {"$subtract": ["$" + a, "$" + b]}, null]
};

// Optional date range on createdAt. Accepts dates (2026-10-05) or full ISO timestamps.
isolated function rangeFilter(string? 'from, string? to) returns map<json> {
    map<json> range = {};
    if 'from is string {
        range["$gte"] = 'from;
    }
    if to is string {
        range["$lte"] = to.length() == 10 ? to + "T23:59:59.999999999Z" : to;
    }
    return range.length() == 0 ? {} : {createdAt: range};
}

isolated function summary(string? 'from, string? to) returns Summary|error {
    map<json>[] pipeline = [
        {"$match": rangeFilter('from, to)},
        {
            "$group": {
                _id: null,
                orders: {"$sum": 1},
                delivered: countIf(DELIVERED_S),
                cancelled: countIf(CANCELLED_S),
                revenue: {"$sum": {"$cond": [{"$eq": ["$status", DELIVERED_S]}, "$totalAmount", 0]}},
                avgEndToEndMs: {"$avg": msBetween("deliveredAtMs", "createdAtMs")}
            }
        },
        {
            "$project": {
                _id: 0, orders: 1, delivered: 1, cancelled: 1, revenue: 1,
                avgEndToEndMinutes: minutes("$avgEndToEndMs")
            }
        }
    ];
    stream<Summary, error?> rows = check facts->aggregate(pipeline, Summary);
    Summary[] result = check from Summary s in rows select s;
    Summary s = result.length() > 0 ? result[0] : {};
    s.inProgress = s.orders - s.delivered - s.cancelled;
    s.cancellationRate = rate(s.cancelled, s.orders);
    return s;
}

isolated function restaurantStats(map<json> filter) returns RestaurantStats[]|error {
    map<json>[] pipeline = [
        {"$match": filter},
        {
            "$group": {
                _id: "$restaurantId",
                orders: {"$sum": 1},
                delivered: countIf(DELIVERED_S),
                cancelled: countIf(CANCELLED_S),
                revenue: {"$sum": {"$cond": [{"$eq": ["$status", DELIVERED_S]}, "$totalAmount", 0]}},
                avgPrepMs: {"$avg": msBetween("readyAtMs", "confirmedAtMs")}
            }
        },
        {
            "$project": {
                _id: 0, restaurantId: "$_id", orders: 1, delivered: 1, cancelled: 1, revenue: 1,
                avgPrepMinutes: minutes("$avgPrepMs")
            }
        },
        {"$sort": {revenue: -1, orders: -1}}
    ];
    stream<RestaurantStats, error?> rows = check facts->aggregate(pipeline, RestaurantStats);
    RestaurantStats[] result = check from RestaurantStats r in rows select r;
    foreach RestaurantStats r in result {
        r.cancellationRate = rate(r.cancelled, r.orders);
    }
    return result;
}

isolated function deliveryPerformance(string? 'from, string? to) returns DeliveryPerformance|error {
    map<json> filter = rangeFilter('from, to);
    filter["deliveredAtMs"] = {"$exists": true};
    map<json> deliveryMs = msBetween("deliveredAtMs", "pickedUpAtMs");
    map<json> endToEndMs = msBetween("deliveredAtMs", "createdAtMs");

    map<json>[] pipeline = [
        {"$match": filter},
        {
            "$group": {
                _id: "$driverId",
                deliveries: {"$sum": 1},
                avgDeliveryMs: {"$avg": deliveryMs},
                avgEndToEndMs: {"$avg": endToEndMs},
                fastestMs: {"$min": deliveryMs},
                slowestMs: {"$max": deliveryMs}
            }
        },
        {
            "$project": {
                _id: 0, driverId: "$_id", deliveries: 1,
                avgDeliveryMinutes: minutes("$avgDeliveryMs"),
                avgEndToEndMinutes: minutes("$avgEndToEndMs"),
                fastestMinutes: minutes("$fastestMs"),
                slowestMinutes: minutes("$slowestMs")
            }
        },
        {"$sort": {deliveries: -1}}
    ];
    stream<DriverStats, error?> rows = check facts->aggregate(pipeline, DriverStats);
    DriverStats[] drivers = check from DriverStats d in rows select d;

    // Overall figures, weighted by each driver's number of deliveries.
    int total = 0;
    float deliverySum = 0;
    float endToEndSum = 0;
    int deliveryN = 0;
    int endToEndN = 0;
    foreach DriverStats d in drivers {
        total += d.deliveries;
        float? avgDelivery = d.avgDeliveryMinutes;
        if avgDelivery is float {
            deliverySum += avgDelivery * <float>d.deliveries;
            deliveryN += d.deliveries;
        }
        float? avgEndToEnd = d.avgEndToEndMinutes;
        if avgEndToEnd is float {
            endToEndSum += avgEndToEnd * <float>d.deliveries;
            endToEndN += d.deliveries;
        }
    }
    return {
        deliveries: total,
        avgDeliveryMinutes: deliveryN > 0 ? round1(deliverySum / <float>deliveryN) : (),
        avgEndToEndMinutes: endToEndN > 0 ? round1(endToEndSum / <float>endToEndN) : (),
        drivers
    };
}

isolated function rate(int part, int whole) returns float =>
    whole == 0 ? 0.0 : round1(<float>part * 100 / <float>whole);

isolated function round1(float x) returns float => <float>(<int>(x * 10 + 0.5)) / 10;
