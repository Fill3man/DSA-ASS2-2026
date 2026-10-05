# restaurant-service (port 8082, database restaurant_db)

Restaurants, digital menus, real-time stock and opening hours. Decides whether each new order can be fulfilled.

**Consumes:** `orders.created` → accept (reserve stock atomically, publish `restaurants.order-accepted` with the pickup location) or reject (closed / unavailable / out of stock → `restaurants.order-rejected`). `orders.cancelled` → return the stock exactly once.

Stock is taken with one atomic update (`stock >= qty` in the filter, `inc -qty`), so two orders can never both take the last portion. `reservations` (unique orderId) makes redelivered events harmless.

| Method | Path | Notes |
|---|---|---|
| GET / POST | `/api/v1/restaurants` | `?cuisine=&openNow=true`; each result includes `openNow` |
| GET | `/api/v1/restaurants/{id}` | |
| PUT | `/api/v1/restaurants/{id}/opening-hours` | `[{day:"MON", open:"08:00", close:"22:00"}]` |
| GET / POST | `/api/v1/restaurants/{id}/menu` | `?availableOnly=true` |
| PATCH | `/api/v1/restaurants/{id}/menu/{itemId}` | price, name, availability... |
| PATCH | `/api/v1/restaurants/{id}/menu/{itemId}/stock` | `{"delta": -3}` or `{"set": 40}`; never below zero |

Config: `enforceOpeningHours` (default true), `utcOffsetHours` (default 2, Namibia).
