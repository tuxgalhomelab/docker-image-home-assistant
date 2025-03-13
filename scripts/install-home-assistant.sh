#!/usr/bin/env bash
set -E -e -o pipefail

export PYENV_ROOT="/opt/pyenv"
export PATH="${PYENV_ROOT:?}/shims:${PYENV_ROOT:?}/bin:/opt/bin:${PATH:?}"

ha_ver="$(ls /wheels/homeassistant-*-py3-none-any.whl | sed -E 's#/wheels/homeassistant-(.+)-py3-none-any.whl#\1#')"
echo "Installing Home Assistant ${ha_ver:?} ..."

cd /opt/home-assistant
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

# Apply patches.
find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p1 -i

# Install go2rtc.
ha_dockerfile_url="https://raw.githubusercontent.com/home-assistant/core/refs/tags/${ha_ver:?}/Dockerfile"
go2rtc_ver=$(homelab download-file ${ha_dockerfile_url:?} | \
    grep 'AlexxIT/go2rtc/releases/download' | \
    sed -E 's#.+github.com/AlexxIT/go2rtc/releases/download/(.+)/go2rtc_linux_.+#\1#')
echo "Installing go2rtc ${go2rtc_ver:?} ..."
go2rtc_arch=$(dpkg --print-architecture)
homelab \
    download-file-as \
    https://github.com/AlexxIT/go2rtc/releases/download/${go2rtc_ver:?}/go2rtc_linux_${go2rtc_arch:?} \
    /opt/home-assistant/bin/go2rtc
chmod +x /opt/home-assistant/bin/go2rtc
/opt/home-assistant/bin/go2rtc --version
