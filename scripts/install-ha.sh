#!/usr/bin/env bash
set -e -o pipefail

ha_ver=${1:?}
echo "Installing Home Assistant ${ha_ver:?} ..."

cd /opt/ha
python3 -m venv .
source bin/activate

# Note that we use a dummy wheels directory (i.e. mounted with the
# valid wheels at the time of Dockerfile build, but not part of the final
# image.). We point the virtualenv pip to this location to prevent
# fetching wheels from anywhere else while HA is running, essentially
# limiting to only the set of installed integrations.
cat << EOF > ${VIRTUAL_ENV:?}/pip.conf
[global]
no-cache-dir = yes
disable-pip-version-check = yes
progress-bar = off

[install]
no-index = yes
find-links = /wheels

[wheel]
no-index = yes
find-links = /wheels

[list]
no-index = yes
find-links = /wheels
EOF

# Install Home Assistant and all the wheels present.
pip3 install --no-cache-dir /wheels/*
