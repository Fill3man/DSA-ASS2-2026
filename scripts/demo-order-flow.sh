#!/usr/bin/env bash
# Walks one order through its whole lifecycle against a running stack, acting
# only as the humans would (customer, restaurant, driver) through REST. Every
# step in between - payment, stock reservation, driver assignment,
# notifications, reports - happens by itself through Kafka events.
#
# Usage (Git Bash on Windows, or any bash):  bash scripts/demo-order-flow.sh
set -euo pipefail

ORDERS=http://localhost:8083/api/v1
DELIVERY=http://localhost:8085/api/v1
NOTIFY=http://localhost:8086/api/v1
ADMIN=http://localhost:8087/api/v1
PAYMENTS=http://localhost:8084/api/v1

field() {   # field <name> : first value of "name":"..." in stdin
  grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

order_status() { curl -s "$ORDERS/orders/$ORDER_ID" | field status; }

wait_for() {  # wait_for <expected order status>
  for _ in $(seq 1 40); do
    [ "$(order_status)" = "$1" ] && { echo "     order status = $1"; return 0; }
    sleep 0.5
  done
  echo "     TIMEOUT: expected $1, got $(order_status)"; exit 1
}

echo "0. Make sure the nearest driver is online"
curl -s -o /dev/null -X PATCH "$DELIVERY/drivers/drv-001/status" -H 'Content-Type: application/json' -d '{"status":"AVAILABLE"}' || true

echo "1. CUSTOMER places an order (REST -> orders.created)"
ORDER_ID=$(curl -s -X POST "$ORDERS/orders" -H 'Content-Type: application/json' -d '{
  "customerId": "cust-001", "restaurantId": "rest-001",
  "items": [{"itemId": "item-001", "name": "Kapana (6 pieces)", "quantity": 2, "unitPrice": 45.00},
            {"itemId": "item-002", "name": "Fat cakes", "quantity": 3, "unitPrice": 15.00}],
  "deliveryAddress": {"street": "12 Robert Mugabe Ave", "city": "Windhoek", "latitude": -22.5700, "longitude": 17.0836}
}' | field orderId)
echo "     orderId = $ORDER_ID"

echo "2. payment-service charges the card, restaurant-service reserves stock (Kafka)"
wait_for CONFIRMED

echo "3. delivery-service assigns the nearest available driver (Kafka)"
for _ in $(seq 1 20); do
  DELIVERY_JSON=$(curl -s "$DELIVERY/deliveries/order/$ORDER_ID")
  [ "$(echo "$DELIVERY_JSON" | field status)" = "ASSIGNED" ] && break
  sleep 0.5
done
DELIVERY_ID=$(echo "$DELIVERY_JSON" | field deliveryId)
echo "     $DELIVERY_ID -> driver $(echo "$DELIVERY_JSON" | field driverId), ETA $(echo "$DELIVERY_JSON" | grep -o '"etaMinutes":[0-9]*' | cut -d: -f2) min"

echo "4. RESTAURANT cooks the food (REST)"
curl -s -o /dev/null -X PATCH "$ORDERS/orders/$ORDER_ID/status" -H 'Content-Type: application/json' -d '{"status":"PREPARING"}'
wait_for PREPARING
curl -s -o /dev/null -X PATCH "$ORDERS/orders/$ORDER_ID/status" -H 'Content-Type: application/json' -d '{"status":"READY"}'
wait_for READY

echo "5. DRIVER picks up and delivers (REST -> delivery.picked-up / delivery.completed)"
sleep 1   # let delivery-service see the READY event
curl -s -o /dev/null -X POST "$DELIVERY/deliveries/$DELIVERY_ID/pickup"
wait_for OUT_FOR_DELIVERY
curl -s -o /dev/null -X POST "$DELIVERY/deliveries/$DELIVERY_ID/complete"
wait_for DELIVERED

echo "6. Guard rails"
echo -n "     cancel a delivered order        -> HTTP "
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$ORDERS/orders/$ORDER_ID/cancel"
echo -n "     PATCH an event-driven status    -> HTTP "
curl -s -o /dev/null -w '%{http_code}\n' -X PATCH "$ORDERS/orders/$ORDER_ID/status" -H 'Content-Type: application/json' -d '{"status":"DELIVERED"}'

sleep 1
echo
echo "Status history:"
curl -s "$ORDERS/orders/$ORDER_ID/history" | grep -o '"status":"[A-Z_]*", "at":"[^"]*", "triggeredBy":"[^"]*"' | sed 's/^/  /'
echo
echo "Payment:        $(curl -s "$PAYMENTS/payments?orderId=$ORDER_ID" | field status)"
echo "Notifications:"
curl -s "$NOTIFY/notifications/order/$ORDER_ID" | grep -o '"channel":"[A-Z]*", "message":"[^"]*"' | sed 's/"channel":"\([A-Z]*\)", "message":"\(.*\)"/  [\1] \2/'
echo
echo "Admin summary:  $(curl -s "$ADMIN/reports/summary")"
