# payment-service (port 8084, database payment_db)

Simulated card payments.

**Consumes:** `orders.created` → PENDING payment → simulated gateway delay → COMPLETED / FAILED → `payments.completed` / `payments.failed`. `orders.cancelled` → COMPLETED becomes REFUNDED; a payment still in flight is abandoned.

One payment per order (unique index on orderId), so a redelivered event never charges twice.

| Method | Path |
|---|---|
| GET | `/api/v1/payments?orderId=&status=` |
| GET | `/api/v1/payments/{paymentId}` |

Config: `cardLimit` (default 2000 - larger orders are declined, a deterministic way to demo failure), `failureRate` (default 0.0 random declines), `minLatency` / `maxLatency` seconds.
