#!/usr/bin/env bash
set -o errexit

for REPO in nginx/nginx:${NGINX_VERSION} nginx/nginx-otel:${NGINX_OTEL_VERSION}; do
    git clone -c advice.detachedHead=false --branch "${REPO#*:}" --depth 1 "https://github.com/${REPO%:*}.git"
done

# Needed for nginx-otel and cmake >= 4
export CMAKE_POLICY_VERSION_MINIMUM=3.5
export GIT_TERMINAL_PROMPT=0

pushd nginx
./auto/configure \
    --with-compat \
    --with-http_ssl_module \
    --with-http_sub_module \
    --with-threads \
    --user=1001 \
    --group=0 \
    --add-dynamic-module="/nginx-otel" \
    --prefix="$NGINX_ROOT"

make -j"$(nproc)"
make -j"$(nproc)" modules
make install

mkdir -pv "${NGINX_ROOT}"/{modules,cache}
cp -v ./objs/ngx_otel_module.so "${NGINX_ROOT}/modules"
ln -sfv /dev/stdout "${NGINX_ROOT}/logs/access.log"
ln -sfv /dev/stderr "${NGINX_ROOT}/logs/error.log"
