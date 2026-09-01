#!/usr/bin/env bash

echo "Waiting for source..."
until [[ -f src/release ]]; do sleep .2; done

echo "Starting build..."
pushd src >/dev/null || exit 1
./mvnw clean install --also-make --projects leaves/leaf-${SERENDITREE_BRANCH}
popd >/dev/null || exit 1

echo "Moving build artifacts..."
mv src/leaves/leaf-${SERENDITREE_BRANCH}/target/serenditree/* .

echo "Starting ${SERENDITREE_SERVICE}..."
[[ "${SERENDITREE_BUILD}" == "native" ]] &&
    _native=-agentlib:native-image-agent=config-output-dir=native,config-write-period-secs=20
exec java $_native -jar ./*.jar
