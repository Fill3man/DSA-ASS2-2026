# delivery-service (port 8085, database delivery_db)

Drivers, dispatch and delivery tracking.

**Consumes:** `orders.created` (drop-off point), `restaurants.order-accepted` (pickup point), `orders.status-changed` (CONFIRMED → dispatch, READY → allows pickup, CANCELLED → release driver, DELIVERED → reconcile).

**Dispatch** (`dispatch.bal`): once an order is paid *and* its pickup point is known, the nearest AVAILABLE driver (haversine, `geo.bal`) is claimed with a compare-and-set (`AVAILABLE → BUSY`), so two orders can't grab the same driver. No driver free → PENDING_DRIVER, assigned as soon as a driver comes online or finishes a job. ETA = driver → restaurant → customer at the vehicle's speed.

| Method | Path | Notes |
|---|---|---|
| GET / POST | `/api/v1/drivers` | `?status=AVAILABLE` |
| PATCH | `/api/v1/drivers/{id}/status` | `AVAILABLE` / `OFFLINE` (409 while BUSY) |
| PUT | `/api/v1/drivers/{id}/location` | publishes `delivery.location-updated` |
| GET | `/api/v1/deliveries?driverId=&status=` | |
| GET | `/api/v1/deliveries/{id}`, `/api/v1/deliveries/order/{orderId}` | |
| POST | `/api/v1/deliveries/{id}/pickup` | only when ASSIGNED and the kitchen marked it READY → `delivery.picked-up` |
| POST | `/api/v1/deliveries/{id}/complete` | PICKED_UP → DELIVERED → `delivery.completed`; driver AVAILABLE |
