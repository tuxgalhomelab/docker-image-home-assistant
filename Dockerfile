# syntax=docker/dockerfile:1.3

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM scratch AS with-scripts
COPY scripts/start-ha.sh scripts/install-ha.sh /scripts/

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG HOME_ASSISTANT_VERSION
ARG PACKAGES_TO_INSTALL

RUN --mount=type=bind,target=/scripts,from=with-scripts,source=/scripts \
    set -e -o pipefail \
    # Install build dependencies. \
    && homelab install util-linux autoconf build-essential python3-dev \
    # Install dependencies. \
    && homelab install $PACKAGES_TO_INSTALL \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/ha \
    # Download and install home assistant, and its dependencies. \
    && chown -R ${USER_NAME:?}:${USER_NAME:?} /opt/ha \
    && su --login --shell /bin/bash --command "/scripts/install-ha.sh ${HOME_ASSISTANT_VERSION:?}" ${USER_NAME:?} \
    # Copy the start-ha.sh script. \
    && cp /scripts/start-ha.sh /opt/ha/ \
    && chown -R ${USER_NAME:?}:${USER_NAME:?} /opt/ha \
    && ln -sf /opt/ha/start-ha.sh /opt/bin/start-ha \
    # Clean up. \
    && rm -rf /home/${USER_NAME:?}/.cache/ \
    && homelab remove util-linux autoconf build-essential python3-dev \
    && homelab cleanup

ENV USER=${USER_NAME}
ENV PATH="/opt/bin:${PATH}"

USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}
CMD ["start-ha"]
EXPOSE 8123
STOPSIGNAL SIGTERM
