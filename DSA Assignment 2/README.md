# Distributed Food Delivery Platform (DSA612S Assignment 2)

Seven Ballerina microservices coordinated through Kafka events, each with its
own MongoDB database, a browser UI, all orchestrated with Docker Compose.

| Service | Port | Owns | Consumes | Publishes |
|---|---|---|---|---|
| customer-service | 8081 | accounts, addresses, order-history read model | orders.created, orders.status-changed | - |
| restaurant-service | 8082 | restaurants, menus, live stock, opening hours | orders.created, orders.cancelled | restaurants.order-accepted / -rejected |
| order-service | 8083 | the order state machine | payments.*, restaurants.order-rejected, delivery.* | orders.created, orders.status-changed, orders.cancelled |
| payment-service | 8084 | simulated card payments, refunds | orders.created, orders.cancelled | payments.completed / failed |
| delivery-service | 8085 | drivers, nearest-driver dispatch, tracking | orders.created, orders.status-changed, restaurants.order-accepted | delivery.assigned / picked-up / completed / location-updated |
| notification-service | 8086 | EMAIL / SMS / PUSH alerts (simulated) | orders.*, delivery.assigned | notifications.sent |
| admin-service | 8087 | reports via Mongo aggregations | orders.*, delivery.assigned | - |
| web (nginx) | **8080** | browser UI for customers, restaurants, drivers, admins | - | - |

## Running it

Prerequisites: Ballerina 2201.13.x, Docker Desktop (give it at least 4 GB of RAM).

```powershell
.\scripts\build-all.ps1          # build the 7 service jars (add -Offline if Ballerina Central is unreachable)
docker compose up -d --build     # start everything
docker compose ps                # wait until every service shows (healthy), ~1-2 min
```

Then open **http://localhost:8080**.

| Tab | You are | Try |
|---|---|---|
| Customer | a customer (pick one at the top) | choose Kapana Corner, add dishes, **Place order**, watch the progress bar move |
| Restaurant | the kitchen | **Start preparing**, then **Mark ready**; adjust stock, switch dishes off |
| Driver | a driver | go online, **Simulate driving** (moves the 🛵 on the map), **Picked up**, **Delivered** |
| Admin | the platform owner | **add restaurants, menu items and drivers**; live totals, per-restaurant stats, delivery performance, payments, every notification |

The **🔔 bell** (top right) is the in-app inbox of whoever you are on the current tab
(customer, restaurant or driver). Every status change of their orders appears there with an
unread badge, and new messages also pop up in the corner.

From the terminal instead: `bash scripts/demo-order-flow.sh` (Git Bash) runs one
order end to end through the REST APIs and prints the history, payment,
notifications and report. [demo.http](demo.http) has every request as a
clickable "Send Request" (VS Code REST Client extension).

### Things to try for the failure paths

* Order **more than NAD 2000** → payment declined (card limit) → order CANCELLED.
* Order from **Joe's Grill on a Monday** (or after 23:00) → restaurant closed → rejected → CANCELLED.
* Order **more than the stock** → rejected; stock is never oversold.
* **Cancel** a CONFIRMED order → payment REFUNDED, stock returned, driver freed.
* Put every driver **offline**, place an order → it waits in PENDING_DRIVER; bring a driver online → assigned instantly.

### Useful commands

```bash
docker compose logs -f order-service           # follow one service
docker compose --profile tools up -d kafka-ui  # Kafka UI at http://localhost:8090 (uses ~300 MB RAM)
docker compose up -d --build order-service     # redeploy one service after rebuilding its jar
docker compose down                            # stop (keeps data)
docker compose down -v                         # stop and wipe all Kafka + Mongo data (fresh seed data)
```

Running one service on the host while developing: `docker compose stop customer-service`,
then `cd services/customer-service && bal run`. (Stop it with Ctrl+C before rebuilding -
a running `bal run` locks the jar.)

## Documentation

* [Architecture](docs/ARCHITECTURE.md): diagrams, order lifecycle, state machine, reliability decisions
* [Event catalogue](docs/EVENTS.md): every topic, its partitions, producers, consumers and payloads
* [Database design](docs/DATABASE.md): database-per-service, schemas, indexes, seed data
* [Defence guide](docs/TEAM_TASKS.md): who presents what, likely questions
* Each service's README: its endpoints and behaviour

## Bonus features

* **Complete UI** - `web/`, served by nginx on 8080.
* **Driver location simulation on a live map** - Driver tab → *Simulate driving*: the browser
  moves the driver toward the restaurant, then the customer, sending each position through
  `PUT /drivers/{id}/location`, which publishes `delivery.location-updated`.
* **Route-aware dispatch** - delivery-service picks the nearest available driver
  (haversine distance) and estimates the ETA from driver → restaurant → customer and vehicle speed.

## Repository layout

```
docker-compose.yml              infrastructure + 7 services + web UI
infra/kafka/create-topics.sh    topics and partition counts
infra/mongo/init-mongo.js       databases, per-service users, validators, indexes, seed data
services/<name>/                one Ballerina package per service (+ Dockerfile, README)
web/                            browser UI (index.html, app.js, style.css)
scripts/                        build-all, demo-order-flow, templates/messaging.bal
docs/                           architecture, events, database, defence guide
```
