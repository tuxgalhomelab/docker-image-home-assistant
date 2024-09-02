# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS builder

ARG HASS_PKG_UTIL_VERSION
ARG HOME_ASSISTANT_VERSION
ARG PY_PKG_PIP_VERSION
ARG PY_PKG_WHEEL_VERSION
ARG PACKAGES_TO_INSTALL

COPY config/disabled-integrations.txt /config/
COPY config/enabled-integrations.txt /config/
COPY config/extra-requirements.txt /config/
COPY scripts/start-hass.sh scripts/install-hass.sh /scripts/
COPY patches /patches

# hadolint ignore=SC1091,SC3040,SC3044
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Install dependencies. \
    && homelab install ${PACKAGES_TO_INSTALL:?} \
    # Install build specific dependencies. \
    && homelab install libcups2-dev \
    # Install hasspkgutil. \
    && homelab install-tuxdude-go-package TuxdudeHomeLab/hasspkgutil ${HASS_PKG_UTIL_VERSION:?} \
    && mkdir -p /root/hass-build /wheels /.wheels-build-info \
    && pushd /root/hass-build \
    # Generate the requirements and constraint list for Home Assistant \
    # Core and also all the integrations we want to enable. \
    && hasspkgutil \
        -mode-generate \
        -ha-version ${HOME_ASSISTANT_VERSION:?} \
        -enabled-integrations /config/enabled-integrations.txt \
        -disabled-integrations /config/disabled-integrations.txt \
        -output-requirements requirements.txt \
        -output-constraints constraints.txt \
    && cat /config/extra-requirements.txt >> requirements.txt \
    && cp requirements.txt /.wheels-build-info/build_requirements.txt \
    && cp constraints.txt /.wheels-build-info/build_constraints.txt \
    # Set up the virtual environment for building the wheels. \
    && python3 -m venv . \
    && source bin/activate \
    && pip3 install --no-cache-dir --progress-bar off --upgrade pip==${PY_PKG_PIP_VERSION:?} \
    && pip3 install --no-cache-dir --progress-bar off --upgrade wheel==${PY_PKG_WHEEL_VERSION:?} \
    # Build the wheels. \
    && MAKEFLAGS="-j$(nproc)" pip3 wheel \
        --no-cache-dir \
        --progress-bar off \
        --wheel-dir=/wheels \
        --find-links=/wheels \
        --requirement requirements.txt \
        --constraint constraints.txt \
    && popd

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG PACKAGES_TO_INSTALL

# hadolint ignore=SC3040
RUN \
    --mount=type=bind,target=/scripts,from=builder,source=/scripts \
    --mount=type=bind,target=/patches,from=builder,source=/patches \
    --mount=type=bind,target=/wheels,from=builder,source=/wheels \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Install build dependencies. \
    && homelab install patch \
    # Install dependencies. \
    && homelab install ${PACKAGES_TO_INSTALL:?} \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    # Add the user to the dialout group to be able to access serial devices \
    # (eg. Zigbee dongle). \
    && usermod --append --groups dialout ${USER_NAME:?} \
    && mkdir -p /opt/hass /config \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /opt/hass /config \
    # Download and install home assistant, and its dependencies. \
    && su --login --shell /bin/bash --command "/scripts/install-hass.sh" ${USER_NAME:?} \
    # Copy the start-hass.sh script. \
    && cp /scripts/start-hass.sh /opt/hass/ \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /opt/hass \
    && ln -sf /opt/hass/start-hass.sh /opt/bin/start-hass \
    # Clean up. \
    && rm -rf /home/${USER_NAME:?}/.cache/ \
    && homelab remove patch \
    && homelab cleanup

EXPOSE 8123

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-hass"]
STOPSIGNAL SIGTERM
