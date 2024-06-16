# syntax=docker/dockerfile:1.3

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS builder

SHELL ["/bin/bash", "-c"]

ARG HASS_PKG_UTIL_VERSION
ARG HOME_ASSISTANT_VERSION
ARG PY_PKG_PIP_VERSION
ARG PY_PKG_WHEEL_VERSION
ARG PACKAGES_TO_INSTALL

RUN \
    set -E -e -o pipefail \
    # Install dependencies. \
    && homelab install ${PACKAGES_TO_INSTALL:?} \
    # Install build specific dependencies. \
    && homelab install libcups2-dev \
    && mkdir -p /config /root/hass /root/hass /wheels /.wheels-build-info /scripts /patches

COPY config/disabled-integrations.txt /config/
COPY config/enabled-integrations.txt /config/
COPY scripts/start-hass.sh scripts/install-hass.sh /scripts/
COPY patches /patches

WORKDIR /root/hass

# hadolint ignore=DL4006,SC1091
RUN \
    set -E -e -o pipefail \
    # Install hasspkgutil. \
    && homelab install-tuxdude-go-package TuxdudeHomeLab/hasspkgutil ${HASS_PKG_UTIL_VERSION:?} \
    # Generate the requirements and constraint list for Home Assistant \
    # Core and also all the integrations we want to enable. \
    && hasspkgutil \
        -mode-generate \
        -ha-version ${HOME_ASSISTANT_VERSION:?} \
        -enabled-integrations /config/enabled-integrations.txt \
        -disabled-integrations /config/disabled-integrations.txt \
        -output-requirements requirements.txt \
        -output-constraints constraints.txt \
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
        --constraint constraints.txt

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG PACKAGES_TO_INSTALL

RUN \
    --mount=type=bind,target=/scripts,from=builder,source=/scripts \
    --mount=type=bind,target=/patches,from=builder,source=/patches \
    --mount=type=bind,target=/wheels,from=builder,source=/wheels \
    set -E -e -o pipefail \
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

ENV USER=${USER_NAME}
ENV PATH="/opt/bin:${PATH}"

USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}
CMD ["start-hass"]
EXPOSE 8123
STOPSIGNAL SIGTERM
