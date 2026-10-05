# customer-service (port 8081, database customer_db)

Customer accounts, delivery addresses, and an order-history read model.

**Consumes:** `orders.created`, `orders.status-changed` (upserts `order_history`; `setOnInsert` so a late `orders.created` never overwrites a newer status)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/customers` | all customers |
| POST | `/api/v1/customers` | `{name, email, phone?, addresses?}`; 409 on duplicate email (unique index) |
| GET / PUT | `/api/v1/customers/{id}` | 404 if unknown |
| GET / POST | `/api/v1/customers/{id}/addresses` | a new default address clears `isDefault` on the others |
| DELETE | `/api/v1/customers/{id}/addresses/{addressId}` | 204 |
| GET | `/api/v1/customers/{id}/orders` | from the local read model - no call to order-service |
