# order-service (port 8083, database order_db): reference implementation

Owns the order state machine `CREATED → CONFIRMED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED` (or `CANCELLED`).

**Consumes:** `payments.completed`, `payments.failed`, `restaurants.order-rejected`, `delivery.assigned`, `delivery.picked-up`, `delivery.completed`
**Publishes:** `orders.created`, `orders.status-changed`, `orders.cancelled`, `orders.dlq`

| File | What it shows |
|---|---|
| `events.bal` | shared event contract (copied to every service) |
| `types.bal` | domain records, typed errors |
| `state_machine.bal` | allowed transitions, who may trigger what |
| `order_logic.bal` | create order; idempotent compare-and-set transitions with retry |
| `repository.bal` | MongoDB access, conditional updates |
| `producer.bal` | acks=all idempotent producer, key = orderId |
| `consumer.bal` | manual commits, retry with backoff, dead-letter topic |
| `main.bal` | REST API, error → HTTP status mapping |
| `tests/` | state machine unit tests (`bal test`) |

API table: see the root README.
