#!/bin/sh
set -eu
umask 077
mkdir -p "${TELEGRAM_PERSONAL_DATA_DIR:-/data}"
chown telegram:telegram "${TELEGRAM_PERSONAL_DATA_DIR:-/data}"
chmod 700 "${TELEGRAM_PERSONAL_DATA_DIR:-/data}"
exec gosu telegram "$@"
