#!/usr/bin/env bash
curl --silent "localhost:${QUARKUS_HTTP_PORT}/q/health/ready"
