#!/usr/bin/env bash
pushd "$KAFKA_PATH" || exit 1
########################################################################################################################
# Format log directories
########################################################################################################################
KAFKA_CLUSTER_ID="$(./bin/kafka-storage.sh random-uuid)"
./bin/kafka-storage.sh format --standalone -t "$KAFKA_CLUSTER_ID" -c config/server.properties
########################################################################################################################
# Create topics once kafka is ready
########################################################################################################################
(
    until ./bin/kafka-broker-api-versions.sh --bootstrap-server "127.0.0.1:${KAFKA_PORT}" &>/dev/null; do sleep .5; done
    for _topic in $KAFKA_TOPICS; do
        echo "Creating topic '$_topic'..."
        ./bin/kafka-topics.sh --create \
            --bootstrap-server "127.0.0.1:${KAFKA_PORT}" \
            --replication-factor 1 \
            --partitions 1 \
            --topic "$_topic"
    done
) &
disown
########################################################################################################################
# Start Kafka
########################################################################################################################
echo "Starting kafka..."
LISTENERS="PLAINTEXT://0.0.0.0:${KAFKA_PORT},CONTROLLER://0.0.0.0:${KRAFT_PORT}"
ADVERTISED="PLAINTEXT://${KAFKA_HOST:-127.0.0.1}:${KAFKA_PORT},CONTROLLER://${KAFKA_HOST:-127.0.0.1}:${KRAFT_PORT}"

exec ./bin/kafka-server-start.sh config/server.properties \
    --override "listeners=$LISTENERS" \
    --override "advertised.listeners=$ADVERTISED" \
    --override "controller.quorum.bootstrap.servers=${KAFKA_HOST:-127.0.0.1}:${KRAFT_PORT}"
