# Architecture

## System overview

Seven Ballerina microservices. They talk to each other **only through Kafka**:
no service calls another service's REST API, and no service reads another
service's database. Clients (web/mobile UI, Postman, curl) call the REST APIs.

```mermaid
flowchart LR
    subgraph Clients
        C[Customer app]
        R[Restaurant dashboard]
        D[Driver app]
        A[Admin]
    end

    subgraph Services["Ballerina services (docker network: food-delivery-backend)"]
        CS[customer-service :8081]
        RS[restaurant-service :8082]
        OS[order-service :8083]
        PS[payment-service :8084]
        DS[delivery-service :8085]
        NS[notification-service :8086]
        AS[admin-service :8087]
    end

    K[(Kafka<br/>KRaft, 12 topics)]

    subgraph Mongo["MongoDB - one database per service"]
        CDB[(customer_db)]
        RDB[(restaurant_db)]
        ODB[(order_db)]
        PDB[(payment_db)]
        DDB[(delivery_db)]
        NDB[(notification_db)]
        ADB[(admin_db)]
    end

    C --> CS & OS
    R --> RS & OS
    D --> DS
    A --> AS

    CS & RS & OS & PS & DS & NS & AS <--> K

    CS --- CDB
    RS --- RDB
    OS --- ODB
    PS --- PDB
    DS --- DDB
    NS --- NDB
    AS --- ADB
```

## Order lifecycle (choreography)

There is no central orchestrator. Each service reacts to events and emits its
own. The order-service owns the state machine and is the only service that
changes an order's status.

```mermaid
sequenceDiagram
    autonumber
    actor Cust as Customer
    participant OS as order-service
    participant K as Kafka
    participant RS as restaurant-service
    participant PS as payment-service
    participant DS as delivery-service
    participant NS as notification-service
    actor Rest as Restaurant
    actor Drv as Driver

    Cust->>OS: POST /orders
    OS->>K: orders.created  (status CREATED)
    K-->>RS: orders.created -> check hours & stock, reserve stock
    K-->>PS: orders.created -> simulate charge
    K-->>NS: orders.created -> "New order" to restaurant
    RS->>K: restaurants.order-accepted (pickup location)
    K-->>DS: remember pickup point
    PS->>K: payments.completed
    K-->>OS: CREATED -> CONFIRMED
    OS->>K: orders.status-changed (CONFIRMED)
    K-->>DS: paid + pickup known -> claim nearest AVAILABLE driver
    DS->>K: delivery.assigned
    K-->>OS: record driverId
    Rest->>OS: PATCH status PREPARING, then READY
    OS->>K: orders.status-changed (PREPARING, READY)
    K-->>NS: "Order ready" to driver
    Drv->>DS: POST /deliveries/{id}/pickup
    DS->>K: delivery.picked-up
    K-->>OS: READY -> OUT_FOR_DELIVERY
    Drv->>DS: POST /deliveries/{id}/complete
    DS->>K: delivery.completed
    K-->>OS: OUT_FOR_DELIVERY -> DELIVERED
    OS->>K: orders.status-changed (DELIVERED)
    K-->>NS: "Delivered" to customer
```

Failure paths: `payments.failed` and `restaurants.order-rejected` both move the
order to `CANCELLED`, and `orders.cancelled` tells payment-service to refund
and restaurant-service to put the stock back.

## Order state machine

```mermaid
stateDiagram-v2
    [*] --> CREATED: POST /orders
    CREATED --> CONFIRMED: payments.completed
    CREATED --> CANCELLED: payments.failed / restaurants.order-rejected / customer
    CONFIRMED --> PREPARING: restaurant (PATCH)
    CONFIRMED --> CANCELLED: customer / restaurant
    PREPARING --> READY: restaurant (PATCH)
    PREPARING --> CANCELLED: restaurant
    READY --> OUT_FOR_DELIVERY: delivery.picked-up
    OUT_FOR_DELIVERY --> DELIVERED: delivery.completed
    DELIVERED --> [*]
    CANCELLED --> [*]
```

Implemented in `services/order-service/state_machine.bal`. The REST API only
lets restaurants set `PREPARING`, `READY` and `CANCELLED`. The other statuses
can only be reached through events, so (for example) nobody can mark an order
`CONFIRMED` without a payment.

## Reliability decisions

| Concern | Decision | Where |
|---|---|---|
| Ordering | Every order-scoped event is keyed by `orderId`, so one order's events stay on one partition and are consumed in order. | `producer.bal` |
| Durable publish | Producer uses `acks=all` and `enableIdempotence=true`: retries never duplicate a message. | `producer.bal` |
| No lost events | `autoCommit: false`. Offsets are committed only after a batch has been processed, so a crash replays events instead of dropping them. | `consumer.bal` |
| Duplicates (at-least-once) | Handlers are idempotent. A transition to the status the order already has is a no-op. Payment and delivery use unique indexes on `orderId`. | `order_logic.bal`, `init-mongo.js` |
| Concurrent updates | Status changes are compare-and-set: `updateOne({orderId, status: <expected>}, ...)`. If two writers race, one gets `modifiedCount == 0`, re-reads and retries. | `repository.bal` |
| Poison messages | Unparseable events go straight to `orders.dlq`. Transient failures are retried with backoff (`maxEventRetries`), then dead-lettered. Business rejections (invalid transition) are logged and skipped. | `consumer.bal` |
| Scaling | A consumer group per service. Topic partition counts (3-6) cap how many replicas can share the work: `docker compose up --scale order-service=3` (remove the fixed host port first). | `create-topics.sh` |
| Service isolation | One MongoDB database **and one Mongo user** per service; each user has `readWrite` on its own database only. | `init-mongo.js`, `docker-compose.yml` |
| Startup order | Compose healthchecks plus `depends_on: condition`: services start only after Kafka is healthy, topics exist (`kafka-init` completed) and Mongo answers pings. `restart: unless-stopped` recovers crashed services. | `docker-compose.yml` |

### Known limitation, worth discussing in the defence

`createOrder` writes to MongoDB and then publishes to Kafka. If the process
dies between the two, the order exists but no `orders.created` event goes out
(the "dual write" problem). The standard fix is a **transactional outbox**:
write the event into an `outbox` collection in the same Mongo transaction as
the order, and have a background task publish and mark outbox rows. That would
make a good extension.
