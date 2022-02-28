#!/usr/bin/env bash
set -e -o pipefail

ver=${1:?}

echo "Installing Home Assistant ${ver:?} ..."
cd /opt/ha
python3 -m venv .
source bin/activate
pip3 install --no-cache-dir wheel
pip3 install --no-cache-dir homeassistant==${ver:?}
