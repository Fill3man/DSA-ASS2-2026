# Database design

MongoDB 7, **database-per-service**. Every collection has a `$jsonSchema`
validator (`validationAction: error`) and indexes, all defined in
`infra/mongo/init-mongo.js`. That script runs automatically the first time the
`mongo` container starts with an empty volume. To re-run it after editing:

```bash
docker compose down -v     # -v deletes the data volumes
docker compose up -d
```

## Why one database per service

* **Isolation.** Each service has its own Mongo user with `readWrite` on its own
  database only. A bug in admin-service cannot corrupt orders.
* **Independent change.** A team can change its schema without coordinating,
  as long as the events it publishes keep their shape.
* **Data that crosses boundaries travels as events.** Services that need
  someone else's data keep a local **read model** built from events, e.g.
  `customer_db.order_history` and `admin_db.order_facts`.

## Collections

| Database | Collection | Key fields | Indexes | Notes |
|---|---|---|---|---|
| customer_db | customers | customerId, email, addresses[] | customerId (unique), email (unique) | Addresses embedded: always read with the customer, small and bounded. |
| customer_db | order_history | orderId, customerId, status | orderId (unique), {customerId, updatedAt} | Read model from `orders.*` events. |
| restaurant_db | restaurants | restaurantId, location, openingHours[] | restaurantId (unique), cuisine | Opening hours embedded (7 rows max). |
| restaurant_db | menu_items | itemId, restaurantId, price, stock, available | itemId (unique), {restaurantId, category} | Separate collection: stock changes on every order, so updates touch one small document. |
| order_db | orders | orderId, status, items[], statusHistory[] | orderId (unique), {customerId, createdAt}, {restaurantId, status}, {status, updatedAt} | Items are a **snapshot** of name and price at order time; later menu changes don't rewrite history. |
| payment_db | payments | paymentId, orderId, status | paymentId (unique), **orderId (unique)**, status | Unique orderId = never charge twice for one order. |
| delivery_db | drivers | driverId, status, location | driverId (unique), status | Seeded with 3 drivers. |
| delivery_db | deliveries | deliveryId, orderId, driverId, status | deliveryId (unique), orderId (unique), {driverId, status} | |
| notification_db | notifications | notificationId, recipientType, recipientId, channel | notificationId (unique), {recipientType, recipientId, createdAt}, orderId | |
| admin_db | order_facts | orderId, restaurantId, status, *At timestamps | orderId (unique), {restaurantId, createdAt}, driverId | One row per order, upserted from events; reports are aggregations over it. |

## Seed data

So you can test immediately:

* customers `cust-001`, `cust-002`
* restaurants `rest-001` (Kapana Corner, open daily 08:00-22:00) and `rest-002` (Joe's Grill, closed Mondays)
* menu items `item-001` to `item-006`
* drivers `drv-001`, `drv-002` (AVAILABLE) and `drv-003` (OFFLINE)

## Connecting

* From the host (Compass, mongosh): `mongodb://root:root-dev-pass@localhost:27017/?authSource=admin`
* As a service user: `mongodb://order_svc:dev-service-pass@localhost:27017/order_db?authSource=order_db`

The passwords are dev defaults; override them in `.env` (see `.env.example`).
