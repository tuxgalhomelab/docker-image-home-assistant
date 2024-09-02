#!/usr/bin/env bash
set -E -e -o pipefail

set_umask() {
    # Configure umask to allow write permissions for the group by default
    # in addition to the owner.
    umask 0002
}

start_home_assistant () {
    echo "Starting Home Assistant ..."
    echo
    cd /opt/home-assistant
    source bin/activate
    exec hass --config /config --log-file /dev/stdout --log-rotate-days 0
}

set_umask
start_home_assistant
