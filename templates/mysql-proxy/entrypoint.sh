#!/bin/bash

# set default values
LISTEN_PORT=${LISTEN_PORT:-3306}
TARGET_HOST=${TARGET_HOST:-external-host}
TARGET_PORT=${TARGET_PORT:-3306}

echo "Starting MySQL proxy..."
echo "Listening on port: $LISTEN_PORT"
echo "Forwarding to: $TARGET_HOST:$TARGET_PORT"

# start socat proxy
exec socat tcp-listen:${LISTEN_PORT},fork,reuseaddr tcp-connect:${TARGET_HOST}:${TARGET_PORT}
