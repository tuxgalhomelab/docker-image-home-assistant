# syntax=docker/dockerfile:1.3

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
ARG WHEELS_IMAGE_NAME
ARG WHEELS_IMAGE_TAG
FROM ${WHEELS_IMAGE_NAME}:${WHEELS_IMAGE_TAG} AS builder

COPY scripts/start-hass.sh scripts/install-hass.sh /scripts/
COPY patches /patches

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
    set -e -o pipefail \
    # Install build dependencies. \
    && homelab install util-linux patch \
    # Install dependencies. \
    && homelab install $PACKAGES_TO_INSTALL \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/hass \
    # Download and install home assistant, and its dependencies. \
    && chown -R ${USER_NAME:?}:${USER_NAME:?} /opt/hass \
    && su --login --shell /bin/bash --command "/scripts/install-hass.sh" ${USER_NAME:?} \
    # Copy the start-hass.sh script. \
    && cp /scripts/start-hass.sh /opt/hass/ \
    && chown -R ${USER_NAME:?}:${USER_NAME:?} /opt/hass \
    && ln -sf /opt/hass/start-hass.sh /opt/bin/start-hass \
    # Clean up. \
    && rm -rf /home/${USER_NAME:?}/.cache/ \
    && homelab remove util-linux patch \
    && homelab cleanup

ENV USER=${USER_NAME}
ENV PATH="/opt/bin:${PATH}"

USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}
CMD ["start-hass"]
EXPOSE 8123
STOPSIGNAL SIGTERM
