# Defence guide

Every member must be in the commit log and able to explain their part. Split
ownership so each person can walk through one service's code and answer
questions on it.

| # | Owner | Explains | Key files |
|---|---|---|---|
| 1 | | order-service: state machine, compare-and-set, DLQ | `state_machine.bal`, `order_logic.bal`, `consumer.bal` |
| 2 | | restaurant-service: atomic stock, opening hours, accept/reject | `repository.bal` (`takeStock`), `hours.bal`, `consumer.bal` |
| 3 | | payment-service: idempotent charging, refund, cancel-in-flight | `consumer.bal` |
| 4 | | delivery-service: nearest-driver dispatch, ETA, pickup/complete | `dispatch.bal`, `geo.bal`, `main.bal` |
| 5 | | notification-service: event → message mapping, dedup | `consumer.bal` |
| 6 | | admin-service: read model + aggregation pipelines | `consumer.bal`, `reports.bal` |
| 7 | | customer-service + MongoDB design (database-per-service, users, validators) | `repository.bal`, `infra/mongo/init-mongo.js`, `docs/DATABASE.md` |
| 8 | | Kafka + Docker: topics, partitions, keys, healthchecks, compose; runs the live demo | `infra/kafka/create-topics.sh`, `docker-compose.yml`, `web/` |

With fewer than 8 members, combine 5+6 and 7+8.

## Live demo script (about 5 minutes)

1. `docker compose ps` - 11 containers, all healthy, each service with its own DB user.
2. Open http://localhost:8080. **Customer**: order 2× Kapana + 3× Fat cakes from Kapana Corner.
3. Watch it go CONFIRMED by itself (payment-service) and get a driver (delivery-service).
4. **Restaurant** tab: Start preparing → Mark ready. Point at the notifications feed.
5. **Driver** tab: Simulate driving (map moves) → Picked up → Delivered.
6. **Admin** tab: revenue, stats, payments, all notifications.
7. Failure path: order something over NAD 2000 → declined → cancelled; or cancel a CONFIRMED order → refund + restock.
8. Optional: `docker compose stop payment-service`, place an order (stays CREATED),
   `docker compose start payment-service` → it catches up from Kafka. This shows why
   asynchronous messaging makes the system fault-tolerant.

## Likely questions

* **Why Kafka instead of services calling each other?** Loose coupling and fault
  tolerance: a service that's down simply catches up from its committed offset (step 8 above).
* **How do you keep one order's events in order?** Key = orderId → same partition → consumed in order.
* **What if an event is delivered twice?** Every handler is idempotent: no-op transitions in
  order-service, unique indexes on orderId in payments/deliveries/reservations, notificationId = eventId + recipient.
* **What if two things update the same order or driver at once?** Compare-and-set updates
  (`updateOne({id, status: expected}, ...)`); only one writer wins, the other retries or backs off.
* **What happens to a malformed event?** Retried 3 times with backoff, then written to `orders.dlq`.
* **How does delivery-service know where the restaurant is without calling it?**
  restaurant-service includes the pickup location in `restaurants.order-accepted`.
* **Why can't the restaurant mark an order DELIVERED?** The REST API only allows PREPARING / READY /
  CANCELLED; CONFIRMED, OUT_FOR_DELIVERY and DELIVERED can only come from payment and delivery events.
* **Weakness?** The dual write in `createOrder` (DB then Kafka) - the fix is a transactional
  outbox (docs/ARCHITECTURE.md).
