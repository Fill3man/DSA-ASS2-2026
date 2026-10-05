# Event catalogue

This is the contract between services. The Ballerina types are in
`services/*/events.bal` (every service has an identical copy, with
`services/order-service/events.bal` as the master). **If you change a
payload, update it here, in order-service's events.bal, and copy that file to
every other service.**

## Conventions

* Values are JSON (UTF-8). Keys are plain strings.
* Every event has `eventId` (UUID), `eventType` and `occurredAt` (ISO-8601 UTC).
* **Key = `orderId`** for every order-scoped event, so all events for one order
  go to one partition, in order. `delivery.location-updated` is keyed by `driverId`.
* Consumers must be **idempotent**: Kafka delivers at least once.
* Consumers must ignore fields they don't know (records are open), so adding a
  field is never a breaking change. Removing or renaming one is.

## Topics

Created by `infra/kafka/create-topics.sh`. Auto-creation is disabled on the
broker, so a typo in a topic name fails loudly instead of silently creating a
new topic.

| Topic | Partitions | Producer | Consumers (group id) | Payload type |
|---|---|---|---|---|
| `orders.created` | 6 | order | restaurant, payment, delivery, customer, notification, admin | `OrderCreatedEvent` |
| `orders.status-changed` | 6 | order | delivery, customer, notification, admin | `OrderStatusChangedEvent` |
| `orders.cancelled` | 3 | order | payment (refund), restaurant (restock) | `OrderCancelledEvent` |
| `payments.completed` | 3 | payment | order | `PaymentCompletedEvent` |
| `payments.failed` | 3 | payment | order | `PaymentFailedEvent` |
| `restaurants.order-accepted` | 3 | restaurant | delivery (pickup location) | `OrderAcceptedEvent` |
| `restaurants.order-rejected` | 3 | restaurant | order | `OrderRejectedEvent` |
| `delivery.assigned` | 3 | delivery | order, notification, admin | `DeliveryAssignedEvent` |
| `delivery.picked-up` | 3 | delivery | order | `DeliveryPickedUpEvent` |
| `delivery.completed` | 3 | delivery | order | `DeliveryCompletedEvent` |
| `delivery.location-updated` | 6 (1 h retention) | delivery | live map (future: websocket push) | `DriverLocationUpdatedEvent` |
| `notifications.sent` | 3 | notification | audit / future consumers | `NotificationSentEvent` |
| `orders.dlq` | 1 (30 d retention) | every service | humans | `DeadLetter` |

Why 6 partitions for `orders.created` and `orders.status-changed`? They're the
busiest topics and have the most consumer groups, so they get room for up to 6
parallel replicas of each consumer. Lower-volume topics get 3.

## Payloads

### orders.created
```json
{
  "eventId": "6f1c...", "eventType": "OrderCreated", "occurredAt": "2026-10-01T10:33:21Z",
  "orderId": "ord-100f...", "customerId": "cust-001", "restaurantId": "rest-001",
  "items": [{"itemId": "item-001", "name": "Kapana (6 pieces)", "quantity": 2, "unitPrice": 45.00}],
  "totalAmount": 135.00, "currency": "NAD",
  "deliveryAddress": {"street": "12 Robert Mugabe Ave", "city": "Windhoek", "postalCode": null, "latitude": null, "longitude": null}
}
```

### orders.status-changed
```json
{
  "eventId": "...", "eventType": "OrderStatusChanged", "occurredAt": "...",
  "orderId": "ord-...", "customerId": "cust-001", "restaurantId": "rest-001", "driverId": "drv-001",
  "fromStatus": "READY", "toStatus": "OUT_FOR_DELIVERY", "triggeredBy": "delivery-service", "reason": null
}
```

### orders.cancelled
```json
{ "eventId": "...", "eventType": "OrderCancelled", "occurredAt": "...",
  "orderId": "ord-...", "customerId": "cust-001", "restaurantId": "rest-001",
  "paymentId": "pay-...", "totalAmount": 135.00, "reason": "cancelled by customer" }
```

### payments.completed / payments.failed
```json
{ "eventId": "...", "eventType": "PaymentCompleted", "occurredAt": "...",
  "orderId": "ord-...", "paymentId": "pay-...", "amount": 135.00, "method": "CARD" }

{ "eventId": "...", "eventType": "PaymentFailed", "occurredAt": "...",
  "orderId": "ord-...", "paymentId": "pay-...", "reason": "card declined" }
```

### restaurants.order-accepted
Stock is reserved. Carries the pickup point so delivery-service can choose the
nearest driver without calling restaurant-service.
```json
{ "eventId": "...", "eventType": "OrderAccepted", "occurredAt": "...",
  "orderId": "ord-...", "restaurantId": "rest-001", "restaurantName": "Kapana Corner",
  "pickupLatitude": -22.5401, "pickupLongitude": 17.0625 }
```

### restaurants.order-rejected
```json
{ "eventId": "...", "eventType": "OrderRejected", "occurredAt": "...",
  "orderId": "ord-...", "restaurantId": "rest-001", "reason": "item-003 out of stock" }
```

### delivery.assigned / delivery.picked-up / delivery.completed
```json
{ "eventId": "...", "eventType": "DeliveryAssigned", "occurredAt": "...",
  "orderId": "ord-...", "deliveryId": "del-...", "driverId": "drv-001", "etaMinutes": 18 }
```
`DeliveryPickedUp` and `DeliveryCompleted` have the same shape, without `etaMinutes`.

### delivery.location-updated (key = driverId)
```json
{ "eventId": "...", "eventType": "DriverLocationUpdated", "occurredAt": "...",
  "driverId": "drv-001", "orderId": "ord-...", "latitude": -22.5609, "longitude": 17.0658 }
```

### orders.dlq
```json
{ "failedAt": "...", "sourceTopic": "payments.completed", "sourcePartition": 1, "sourceOffset": 1,
  "errorMessage": "{ballerina/lang.value}FromJsonStringError", "rawValue": "this is not json" }
```

## Watching events

```bash
# everything on a topic, with keys and partitions
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:29092 \
  --topic orders.status-changed --from-beginning --property print.key=true --property print.partition=true

# lag per partition for a consumer group
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:29092 \
  --describe --group order-service
```

Or start Kafka UI: `docker compose --profile tools up -d kafka-ui` and open http://localhost:8090.
