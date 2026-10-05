import ballerina/http;
import ballerina/log;
import ballerina/uuid;

type DriverCreated record {|
    *http:Created;
    Driver body;
|};

type DeliveryResponse Delivery|http:NotFound|http:Conflict|http:InternalServerError;

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    // ---- drivers

    resource function get drivers(DriverStatus? status = ()) returns Driver[]|http:InternalServerError {
        Driver[]|error result = listDrivers(status is DriverStatus ? {status} : {});
        return result is error ? internalError(result) : result;
    }

    resource function get drivers/[string driverId]() returns Driver|http:NotFound|http:InternalServerError {
        Driver|error d = findDriver(driverId);
        return d is error ? notFoundOr500(d) : d;
    }

    resource function post drivers(NewDriver req) returns DriverCreated|http:InternalServerError {
        Driver d = {
            driverId: "drv-" + uuid:createType4AsString().substring(0, 8),
            name: req.name,
            phone: req?.phone,
            vehicle: req.vehicle,
            status: OFFLINE,
            location: req.location,
            updatedAt: nowIso()
        };
        error? saved = insertDriver(d);
        if saved is error {
            return internalError(saved);
        }
        return <DriverCreated>{headers: {"Location": "/api/v1/drivers/" + d.driverId}, body: d};
    }

    // Driver goes online or offline. BUSY is set by the system, not by hand.
    resource function patch drivers/[string driverId]/status(DriverStatusChange req)
            returns Driver|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        if req.status == BUSY {
            return <http:BadRequest>{body: <ErrorBody>{message: "BUSY is set automatically when a delivery is assigned"}};
        }
        do {
            Driver d = check findDriver(driverId);
            if d.status == BUSY {
                return <http:Conflict>{body: <ErrorBody>{message: "driver is on a delivery; finish it first"}};
            }
            _ = check setDriverStatusIf(driverId, d.status, req.status);
            if req.status == AVAILABLE {
                assignQueued(); // a waiting order may now get this driver
            }
            return check findDriver(driverId);
        } on fail error e {
            return notFoundOr500(e);
        }
    }

    // Live location from the driver app (or the simulator in the web UI).
    resource function put drivers/[string driverId]/location(GeoPoint req)
            returns Driver|http:NotFound|http:InternalServerError {
        do {
            if !check setDriverLocation(driverId, req) {
                return <http:NotFound>{body: <ErrorBody>{message: string `driver ${driverId} not found`}};
            }
            Delivery[] active = check listDeliveries({driverId, status: {"$in": [ASSIGNED, PICKED_UP]}});
            check publish(TOPIC_DELIVERY_LOCATION_UPDATED, driverId, <DriverLocationUpdatedEvent>{
                eventId: newEventId(), occurredAt: nowIso(), driverId,
                orderId: active.length() > 0 ? active[0].orderId : (),
                latitude: req.latitude, longitude: req.longitude
            });
            return check findDriver(driverId);
        } on fail error e {
            return notFoundOr500(e);
        }
    }

    // ---- deliveries

    resource function get deliveries(string? driverId = (), DeliveryStatus? status = ())
            returns Delivery[]|http:InternalServerError {
        map<json> filter = {};
        if driverId is string {
            filter["driverId"] = driverId;
        }
        if status is DeliveryStatus {
            filter["status"] = status;
        }
        Delivery[]|error result = listDeliveries(filter);
        return result is error ? internalError(result) : result;
    }

    resource function get deliveries/[string deliveryId]() returns DeliveryResponse {
        return toResponse(findDelivery({deliveryId}));
    }

    resource function get deliveries/'order/[string orderId]() returns DeliveryResponse {
        return toResponse(findDelivery({orderId}));
    }

    // Driver collects the food. Only once the restaurant has marked it READY.
    resource function post deliveries/[string deliveryId]/pickup() returns DeliveryResponse {
        do {
            Delivery d = check findDelivery({deliveryId});
            if d.status != ASSIGNED {
                fail error ConflictError(string `delivery is ${d.status}, expected ASSIGNED`);
            }
            if d?.orderStatus != READY {
                fail error ConflictError(string `the food isn't ready yet (order is ${d?.orderStatus ?: "unknown"})`);
            }
            if !check updateDeliveryIf(d.orderId, ASSIGNED, {status: PICKED_UP, pickedUpAt: nowIso()}) {
                fail error ConflictError("delivery changed concurrently, try again");
            }
            check publish(TOPIC_DELIVERY_PICKED_UP, d.orderId, <DeliveryPickedUpEvent>{
                eventId: newEventId(), occurredAt: nowIso(), orderId: d.orderId,
                deliveryId, driverId: d?.driverId ?: ""
            });
            log:printInfo("food picked up", orderId = d.orderId, driverId = d?.driverId);
            return check findDelivery({deliveryId});
        } on fail error e {
            return toResponse(e);
        }
    }

    // Driver hands the food over; the driver becomes available again.
    resource function post deliveries/[string deliveryId]/complete() returns DeliveryResponse {
        do {
            Delivery d = check findDelivery({deliveryId});
            if !check updateDeliveryIf(d.orderId, PICKED_UP, {status: DELIVERED, deliveredAt: nowIso()}) {
                fail error ConflictError(string `delivery is ${d.status}, expected PICKED_UP`);
            }
            string driverId = d?.driverId ?: "";
            check publish(TOPIC_DELIVERY_COMPLETED, d.orderId, <DeliveryCompletedEvent>{
                eventId: newEventId(), occurredAt: nowIso(), orderId: d.orderId, deliveryId, driverId
            });
            _ = check setDriverStatusIf(driverId, BUSY, AVAILABLE);
            log:printInfo("delivered", orderId = d.orderId, driverId = driverId);
            assignQueued();
            return check findDelivery({deliveryId});
        } on fail error e {
            return toResponse(e);
        }
    }
}

isolated function toResponse(Delivery|error result) returns DeliveryResponse {
    if result is ConflictError {
        return <http:Conflict>{body: <ErrorBody>{message: result.message()}};
    }
    if result is error {
        return notFoundOr500(result);
    }
    return result;
}

isolated function notFoundOr500(error e) returns http:NotFound|http:InternalServerError {
    if e is NotFoundError {
        return <http:NotFound>{body: <ErrorBody>{message: e.message()}};
    }
    return internalError(e);
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("request failed", e);
    return {body: <ErrorBody>{message: "internal error"}};
}
