#!/usr/bin/env bash
set -e -o pipefail

start_home_assistant () {
    echo "Starting Home Assistant ..."
    echo
    cd /opt/ha
    source bin/activate
    exec hass --config /config --log-file /dev/stdout --log-rotate-days 0
}

start_home_assistant
