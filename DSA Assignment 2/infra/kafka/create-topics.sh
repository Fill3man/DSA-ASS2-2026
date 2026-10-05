#!/bin/bash
# Creates every topic the platform uses, with explicit partition counts.
# Runs once in the `kafka-init` container; safe to re-run (--if-not-exists).
#
# Partitioning rule: order-scoped events use key = orderId, so all events for
# one order go to the same partition and are consumed in order. The partition
# count is the ceiling on how many replicas of a consumer group can work in
# parallel, so busy topics get more partitions.
set -euo pipefail

BOOTSTRAP="${BOOTSTRAP:-kafka:29092}"
KT=/opt/kafka/bin/kafka-topics.sh

echo "Waiting for Kafka at $BOOTSTRAP ..."
until $KT --bootstrap-server "$BOOTSTRAP" --list >/dev/null 2>&1; do sleep 2; done

create() {
  local topic=$1 partitions=$2 retention_ms=${3:-604800000}   # default 7 days
  $KT --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
      --topic "$topic" --partitions "$partitions" --replication-factor 1 \
      --config retention.ms="$retention_ms"
}

# topic                          partitions  retention
create orders.created              6
create orders.status-changed       6
create orders.cancelled            3
create payments.completed          3
create payments.failed             3
create restaurants.order-rejected  3
create restaurants.order-accepted  3
create delivery.assigned           3
create delivery.picked-up          3
create delivery.completed          3
create delivery.location-updated   6   3600000     # high volume, keep 1 hour
create notifications.sent          3
create orders.dlq                  1   2592000000  # 30 days, for investigation

echo "Topics:"
$KT --bootstrap-server "$BOOTSTRAP" --describe | grep -E '^Topic:' | awk '{print "  " $2 " partitions=" $6}'
