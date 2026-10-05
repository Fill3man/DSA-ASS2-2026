# admin-service (port 8087, database admin_db)

Reports on restaurant statistics and delivery performance.

**Consumes:** `orders.created`, `orders.status-changed`, `delivery.assigned` → upserts one `order_facts` document per order, with a timestamp (ISO and epoch-ms) for every stage.

Every report is a MongoDB **aggregation pipeline** (`reports.bal`); admin never calls another service.

| Method | Path | Returns |
|---|---|---|
| GET | `/api/v1/reports/summary?from=&to=` | orders, delivered, cancelled, in progress, revenue, cancellation rate, avg order→door minutes |
| GET | `/api/v1/reports/restaurants?from=&to=` | per restaurant: orders, delivered, cancelled, revenue, avg prep minutes |
| GET | `/api/v1/reports/restaurants/{id}` | one restaurant |
| GET | `/api/v1/reports/delivery-performance?from=&to=` | overall + per driver: avg/fastest/slowest pickup→door, avg order→door |

`from` / `to` accept `2026-10-05` or full ISO timestamps.
