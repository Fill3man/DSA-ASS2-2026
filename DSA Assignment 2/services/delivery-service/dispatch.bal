import ballerina/log;

// Driver assignment. A delivery is assigned once it is both CONFIRMED
// (payment went through) and has a pickup point (restaurant accepted the
// order). Those arrive on different topics in either order, so every
// relevant event calls tryAssign() and the last one to arrive does the work.

isolated function tryAssign(string orderId) returns error? {
    Delivery d = check findDelivery({orderId});
    GeoPoint? pickup = d?.pickup;
    if d.status != PENDING_DRIVER || pickup is () || !isPaid(d) {
        return;
    }

    Driver[] candidates = check listDrivers({status: AVAILABLE});
    if candidates.length() == 0 {
        log:printWarn("no driver available, delivery queued", orderId = orderId);
        return;
    }
    // Nearest first.
    Driver[] byDistance = from Driver c in candidates
        order by distanceKm(c.location, pickup) ascending
        select c;

    foreach Driver driver in byDistance {
        if !check setDriverStatusIf(driver.driverId, AVAILABLE, BUSY) {
            continue; // someone else claimed this driver a moment ago
        }
        int eta = etaMinutes(driver, pickup, d?.dropoff);
        boolean assigned = check updateDeliveryIf(orderId, PENDING_DRIVER,
                {driverId: driver.driverId, status: ASSIGNED, assignedAt: nowIso(), etaMinutes: eta});
        if !assigned {
            // The delivery was assigned or cancelled concurrently; free the driver.
            _ = check setDriverStatusIf(driver.driverId, BUSY, AVAILABLE);
            return;
        }
        check publish(TOPIC_DELIVERY_ASSIGNED, orderId, <DeliveryAssignedEvent>{
            eventId: newEventId(), occurredAt: nowIso(), orderId,
            deliveryId: d.deliveryId, driverId: driver.driverId, etaMinutes: eta
        });
        log:printInfo("driver assigned", orderId = orderId, driverId = driver.driverId,
                distanceKm = distanceKm(driver.location, pickup), etaMinutes = eta);
        return;
    }
}

// Retry every queued delivery - called when a driver becomes free.
isolated function assignQueued() {
    Delivery[]|error queued = listDeliveries({status: PENDING_DRIVER});
    if queued is error {
        log:printError("could not load queued deliveries", queued);
        return;
    }
    foreach Delivery d in queued {
        error? result = tryAssign(d.orderId);
        if result is error {
            log:printError("assignment failed", result, orderId = d.orderId);
        }
    }
}

// Once payment has confirmed the order it moves past CREATED for good.
isolated function isPaid(Delivery d) returns boolean {
    string? s = d?.orderStatus;
    return s is string && s != CREATED && s != CANCELLED;
}
