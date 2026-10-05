// Runs once, the first time the mongo container starts with an empty volume
// (docker-entrypoint-initdb.d). To re-run: `docker compose down -v`.
//
// Database-per-service: each microservice owns one database and no service
// reads another service's database. Data that crosses boundaries travels as
// Kafka events, and services keep their own read models (e.g.
// customer_db.order_history, admin_db.order_facts).

// Each service connects as its own user with readWrite on its own database
// only - order-service physically cannot read payment_db.
const SERVICE_PASSWORD = process.env.MONGO_SERVICE_PASSWORD || "dev-service-pass";

function setup(dbName, collections) {
  const d = db.getSiblingDB(dbName);
  const user = dbName.replace("_db", "_svc");
  d.createUser({ user, pwd: SERVICE_PASSWORD, roles: [{ role: "readWrite", db: dbName }] });
  for (const [name, spec] of Object.entries(collections)) {
    d.createCollection(name, {
      validator: { $jsonSchema: spec.schema },
      validationLevel: "moderate",
      validationAction: "error",
    });
    for (const [keys, opts] of spec.indexes || []) {
      d.getCollection(name).createIndex(keys, opts || {});
    }
    if (spec.seed && spec.seed.length) {
      d.getCollection(name).insertMany(spec.seed);
    }
  }
  print(`initialised ${dbName}: ${Object.keys(collections).join(", ")}`);
}

const str = { bsonType: "string" };
const num = { bsonType: "number" };
const int = { bsonType: ["int", "long"] };
const bool = { bsonType: "bool" };
const optStr = { bsonType: ["string", "null"] };
const geo = {
  bsonType: "object",
  required: ["latitude", "longitude"],
  properties: { latitude: num, longitude: num },
};
const address = {
  bsonType: "object",
  required: ["street", "city"],
  properties: { street: str, city: str, postalCode: optStr },
};
const ORDER_STATUSES = ["CREATED", "CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY", "DELIVERED", "CANCELLED"];
const now = new Date().toISOString();

// ---------------------------------------------------------------- customer
setup("customer_db", {
  customers: {
    schema: {
      bsonType: "object",
      required: ["customerId", "name", "email", "addresses", "createdAt"],
      properties: {
        customerId: str, name: str, email: str, phone: optStr, createdAt: str,
        addresses: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["addressId", "label", "street", "city"],
            properties: { addressId: str, label: str, street: str, city: str, isDefault: bool },
          },
        },
      },
    },
    indexes: [[{ customerId: 1 }, { unique: true }], [{ email: 1 }, { unique: true }]],
    seed: [
      {
        customerId: "cust-001", name: "Ndapewa Shilongo", email: "ndapewa@example.com", phone: "+264811234567",
        createdAt: now,
        addresses: [{ addressId: "addr-001", label: "Home", street: "12 Robert Mugabe Ave", city: "Windhoek",
                      postalCode: "10005", latitude: -22.5700, longitude: 17.0836, isDefault: true }],
      },
      {
        customerId: "cust-002", name: "Johannes Nghipandulwa", email: "johannes@example.com", phone: "+264817654321",
        createdAt: now,
        addresses: [{ addressId: "addr-002", label: "Work", street: "13 Jackson Kaujeua St", city: "Windhoek",
                      postalCode: "10001", latitude: -22.5649, longitude: 17.0757, isDefault: true }],
      },
    ],
  },
  // Read model built from orders.* events - lets customers see their history
  // without calling order-service.
  order_history: {
    schema: {
      bsonType: "object",
      required: ["orderId", "customerId", "status", "updatedAt"],
      properties: { orderId: str, customerId: str, restaurantId: str, status: { enum: ORDER_STATUSES },
                    totalAmount: num, updatedAt: str },
    },
    indexes: [[{ orderId: 1 }, { unique: true }], [{ customerId: 1, updatedAt: -1 }]],
  },
});

// -------------------------------------------------------------- restaurant
setup("restaurant_db", {
  restaurants: {
    schema: {
      bsonType: "object",
      required: ["restaurantId", "name", "address", "location", "openingHours"],
      properties: {
        restaurantId: str, name: str, cuisine: str, address, location: geo,
        openingHours: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["day", "open", "close"],
            properties: {
              day: { enum: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] },
              open: { bsonType: "string", pattern: "^[0-2][0-9]:[0-5][0-9]$" },
              close: { bsonType: "string", pattern: "^[0-2][0-9]:[0-5][0-9]$" },
            },
          },
        },
      },
    },
    indexes: [[{ restaurantId: 1 }, { unique: true }], [{ cuisine: 1 }]],
    seed: [
      {
        // Open around the clock so demos work at any hour; Joe's Grill below
        // keeps real hours (closed Mondays) to show the "closed" rejection.
        restaurantId: "rest-001", name: "Kapana Corner", cuisine: "Namibian",
        address: { street: "Single Quarters", city: "Windhoek" },
        location: { latitude: -22.5401, longitude: 17.0625 },
        openingHours: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].map(d => ({ day: d, open: "00:00", close: "23:59" })),
      },
      {
        restaurantId: "rest-002", name: "Joe's Grill", cuisine: "Grill",
        address: { street: "160 Mandume Ndemufayo Ave", city: "Windhoek" },
        location: { latitude: -22.5822, longitude: 17.0868 },
        openingHours: ["TUE", "WED", "THU", "FRI", "SAT", "SUN"].map(d => ({ day: d, open: "11:00", close: "23:00" })),
      },
    ],
  },
  // Menu items are a separate collection (not embedded) because stock changes
  // on every order; updating one small document beats rewriting a whole menu.
  menu_items: {
    schema: {
      bsonType: "object",
      required: ["itemId", "restaurantId", "name", "price", "available", "stock"],
      properties: {
        itemId: str, restaurantId: str, name: str, description: str, category: str,
        price: { bsonType: "number", minimum: 0 },
        available: bool,
        stock: { bsonType: ["int", "long"], minimum: 0 },
      },
    },
    indexes: [[{ itemId: 1 }, { unique: true }], [{ restaurantId: 1, category: 1 }]],
    seed: [
      { itemId: "item-001", restaurantId: "rest-001", name: "Kapana (6 pieces)", category: "Mains", price: 45.0, available: true, stock: 100 },
      { itemId: "item-002", restaurantId: "rest-001", name: "Fat cakes", category: "Sides", price: 15.0, available: true, stock: 200 },
      { itemId: "item-003", restaurantId: "rest-001", name: "Oshifima & stew", category: "Mains", price: 65.0, available: true, stock: 50 },
      { itemId: "item-004", restaurantId: "rest-002", name: "Eisbein", category: "Mains", price: 189.0, available: true, stock: 20 },
      { itemId: "item-005", restaurantId: "rest-002", name: "Game burger", category: "Mains", price: 125.0, available: true, stock: 40 },
      { itemId: "item-006", restaurantId: "rest-002", name: "Rock shandy", category: "Drinks", price: 38.0, available: true, stock: 150 },
    ],
  },
});

// ------------------------------------------------------------------- order
setup("order_db", {
  orders: {
    schema: {
      bsonType: "object",
      required: ["orderId", "customerId", "restaurantId", "items", "totalAmount", "status", "statusHistory", "createdAt"],
      properties: {
        orderId: str, customerId: str, restaurantId: str, currency: str,
        totalAmount: { bsonType: "number", minimum: 0 },
        status: { enum: ORDER_STATUSES },
        items: {
          bsonType: "array", minItems: 1,
          items: {
            bsonType: "object",
            required: ["itemId", "name", "quantity", "unitPrice"],
            properties: { itemId: str, name: str, quantity: { bsonType: ["int", "long"], minimum: 1 },
                          unitPrice: { bsonType: "number", minimum: 0 } },
          },
        },
        statusHistory: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["status", "at", "triggeredBy"],
            properties: { status: { enum: ORDER_STATUSES }, at: str, triggeredBy: str, reason: optStr },
          },
        },
        paymentId: optStr, deliveryId: optStr, driverId: optStr, createdAt: str, updatedAt: str,
      },
    },
    indexes: [
      [{ orderId: 1 }, { unique: true }],
      [{ customerId: 1, createdAt: -1 }],
      [{ restaurantId: 1, status: 1 }],
      [{ status: 1, updatedAt: 1 }],
    ],
  },
});

// ----------------------------------------------------------------- payment
setup("payment_db", {
  payments: {
    schema: {
      bsonType: "object",
      required: ["paymentId", "orderId", "amount", "status", "createdAt"],
      properties: {
        paymentId: str, orderId: str, amount: num, currency: str, method: str,
        status: { enum: ["PENDING", "COMPLETED", "FAILED", "REFUNDED"] },
        attempts: int, failureReason: optStr, createdAt: str, updatedAt: str,
      },
    },
    // Unique orderId = at most one payment per order. If orders.created is
    // delivered twice, the second insert fails instead of charging twice.
    indexes: [[{ paymentId: 1 }, { unique: true }], [{ orderId: 1 }, { unique: true }], [{ status: 1 }]],
  },
});

// ---------------------------------------------------------------- delivery
setup("delivery_db", {
  drivers: {
    schema: {
      bsonType: "object",
      required: ["driverId", "name", "status", "location"],
      properties: {
        driverId: str, name: str, phone: str, vehicle: str,
        status: { enum: ["AVAILABLE", "BUSY", "OFFLINE"] },
        location: geo, updatedAt: str,
      },
    },
    indexes: [[{ driverId: 1 }, { unique: true }], [{ status: 1 }]],
    seed: [
      { driverId: "drv-001", name: "Petrus Amutenya", phone: "+264812000001", vehicle: "Motorbike", status: "AVAILABLE",
        location: { latitude: -22.5609, longitude: 17.0658 }, updatedAt: now },
      { driverId: "drv-002", name: "Selma Iipinge", phone: "+264812000002", vehicle: "Car", status: "AVAILABLE",
        location: { latitude: -22.5750, longitude: 17.0900 }, updatedAt: now },
      { driverId: "drv-003", name: "Tangeni Hamutenya", phone: "+264812000003", vehicle: "Bicycle", status: "OFFLINE",
        location: { latitude: -22.5500, longitude: 17.0700 }, updatedAt: now },
    ],
  },
  deliveries: {
    schema: {
      bsonType: "object",
      required: ["deliveryId", "orderId", "status"],
      properties: {
        deliveryId: str, orderId: str, driverId: optStr,
        status: { enum: ["PENDING_DRIVER", "ASSIGNED", "PICKED_UP", "DELIVERED", "FAILED"] },
        pickup: geo, dropoff: geo, etaMinutes: { bsonType: ["int", "long", "null"] },
        assignedAt: optStr, pickedUpAt: optStr, deliveredAt: optStr,
      },
    },
    indexes: [[{ deliveryId: 1 }, { unique: true }], [{ orderId: 1 }, { unique: true }], [{ driverId: 1, status: 1 }]],
  },
});

// ------------------------------------------------------------ notification
setup("notification_db", {
  notifications: {
    schema: {
      bsonType: "object",
      required: ["notificationId", "recipientType", "recipientId", "channel", "message", "createdAt"],
      properties: {
        notificationId: str, orderId: optStr, eventType: str,
        recipientType: { enum: ["CUSTOMER", "RESTAURANT", "DRIVER"] },
        recipientId: str,
        channel: { enum: ["EMAIL", "SMS", "PUSH", "IN_APP"] },
        message: str,
        status: { enum: ["SENT", "FAILED"] },
        read: bool,
        createdAt: str,
      },
    },
    indexes: [
      [{ notificationId: 1 }, { unique: true }],
      [{ recipientType: 1, recipientId: 1, createdAt: -1 }],
      [{ recipientType: 1, recipientId: 1, channel: 1, read: 1 }],   // unread badge count
      [{ orderId: 1 }],
    ],
  },
});

// ------------------------------------------------------------------- admin
setup("admin_db", {
  // One document per order, upserted as events arrive. Reports are Mongo
  // aggregations over this collection - admin-service never calls the others.
  order_facts: {
    schema: {
      bsonType: "object",
      required: ["orderId", "restaurantId", "status"],
      properties: {
        orderId: str, restaurantId: str, customerId: str, driverId: optStr,
        status: { enum: ORDER_STATUSES },
        totalAmount: num,
        createdAt: optStr, confirmedAt: optStr, readyAt: optStr, pickedUpAt: optStr, deliveredAt: optStr, cancelledAt: optStr,
      },
    },
    indexes: [[{ orderId: 1 }, { unique: true }], [{ restaurantId: 1, createdAt: -1 }], [{ driverId: 1 }]],
  },
});
