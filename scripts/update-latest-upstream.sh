#!/usr/bin/env bash

set -e -o pipefail

script_parent_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
git_repo_dir="$(realpath "${script_parent_dir:?}/..")"

ARGS_FILE="${git_repo_dir:?}/config/ARGS"
ENABLED_INTGRATIONS_FILE="${git_repo_dir:?}/config/enabled-integrations.txt"
DISABLED_INTGRATIONS_FILE="${git_repo_dir:?}/config/disabled-integrations.txt"

git_repo_get_all_tags() {
    git_repo="${1:?}"
    git -c 'versionsort.suffix=-' ls-remote \
        --exit-code \
        --refs \
        --sort='version:refname' \
        --tags \
        ${git_repo:?} '*.*.*' | \
        cut --delimiter='/' --fields=3 | \
        grep -P -v '^.+\.\d+b\d+$'
}

git_repo_latest_tag() {
    git_repo="${1:?}"
    # Strip out any strings that begin with 'v' before identifying the highest semantic version.
    highest_sem_ver_tag=$(git_repo_get_all_tags ${git_repo:?} | sed -E s'#^v(.*)$#\1#g' | sed '/-/!{s/$/_/}' | sort --version-sort | sed 's/_$//'| tail -1)
    # Identify the correct tag for the semantic version of interest.
    git_repo_get_all_tags ${git_repo:?} | grep -E "${highest_sem_ver_tag//./\\.}$" | cut --delimiter='/' --fields=3
}

update_integration_files() {
    ha_version="${1:?}"
    hasspkgutil_version=$(get_config_arg "HASS_PKG_UTIL_VERSION")
    base_image=$(get_config_arg "BASE_IMAGE_NAME"):$(get_config_arg "BASE_IMAGE_TAG")
    docker run --rm -v ${ENABLED_INTGRATIONS_FILE:?}:/root/ei.txt -v ${DISABLED_INTGRATIONS_FILE:?}:/root/di.txt ${base_image:?} sh -c "homelab install-tuxdude-go-package TuxdudeHomeLab/hasspkgutil ${hasspkgutil_version:?} >/dev/null 2>&1 && hasspkgutil -mode-update -ha-version ${ha_version:?} -enabled-integrations /root/ei.txt -disabled-integrations /root/di.txt"
}

get_config_arg() {
    arg="${1:?}"
    sed -n -E "s/^${arg:?}=(.*)\$/\\1/p" ${ARGS_FILE:?}
}

set_config_arg() {
    arg="${1:?}"
    val="${2:?}"
    sed -i -E "s/^${arg:?}=(.*)\$/${arg:?}=${val:?}/" ${ARGS_FILE:?}
}

pkg="Home Assistant"
repo_url="https://github.com/home-assistant/core.git"
config_ver_key="HOME_ASSISTANT_VERSION"

existing_upstream_ver=$(get_config_arg ${config_ver_key:?})
latest_upstream_ver=$(git_repo_latest_tag ${repo_url:?})

if [[ "${existing_upstream_ver:?}" == "${latest_upstream_ver:?}" ]]; then
    echo "Existing config is already up to date and pointing to the latest upstream ${pkg:?} version '${latest_upstream_ver:?}'"
else
    update_integration_files "${latest_upstream_ver:?}"

    echo "Updating ${pkg:?} ${config_ver_key:?} '${existing_upstream_ver:?}' -> '${latest_upstream_ver:?}'"
    set_config_arg "${config_ver_key:?}" "${latest_upstream_ver:?}"
    git add ${ARGS_FILE:?} ${ENABLED_INTGRATIONS_FILE:?} ${DISABLED_INTGRATIONS_FILE:?}
    git commit -m "feat: Bump upstream ${pkg:?} version to ${latest_upstream_ver:?}."
fi
