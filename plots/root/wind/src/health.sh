#!/usr/bin/env bash
# shellcheck disable=SC2086
${KAFKA_PATH}/bin/kafka-broker-api-versions.sh --bootstrap-server "127.0.0.1:${KAFKA_PORT}" &>/dev/null
