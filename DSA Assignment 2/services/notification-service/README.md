# notification-service (port 8086, database notification_db)

Multi-channel alerts to customers, restaurants and drivers. Sending is simulated: each message is logged, stored, and published to `notifications.sent`.

**Consumes:** `orders.created`, `orders.status-changed`, `delivery.assigned`.

| Event | Recipient | Channel |
|---|---|---|
| orders.created | restaurant, customer | PUSH, EMAIL |
| CONFIRMED | customer | EMAIL |
| PREPARING / READY | customer (+ driver on READY) | PUSH |
| OUT_FOR_DELIVERY / DELIVERED / CANCELLED | customer (+ restaurant) | SMS |
| delivery.assigned | driver | PUSH |

**In-app notifications (`IN_APP` channel, `inapp.bal`):** on every order event, each party to the order gets a message worded for their role: the customer and the restaurant from the start, and the driver from the moment they're assigned. The service keeps a small `order_parties` collection (orderId → customer, restaurant, driver) so it knows who to tell even when an event doesn't carry every id. The web UI shows these in the 🔔 bell, with an unread badge and pop-ups.

`notificationId = eventId:channel:recipientType:recipientId` with a unique index → a redelivered event never notifies twice.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/notifications?recipientType=&recipientId=&channel=&unreadOnly=&limit=` | newest first; `channel=IN_APP` for the in-app inbox |
| GET | `/api/v1/notifications/order/{orderId}` | everything sent about one order |
| GET | `/api/v1/notifications/unread-count?recipientType=&recipientId=` | `{"count": n}` - unread IN_APP messages |
| POST | `/api/v1/notifications/mark-read` | `{"recipientType":"CUSTOMER","recipientId":"cust-001"}` |
