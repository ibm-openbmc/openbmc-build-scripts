#!/bin/bash -xe

# This build script is for running the Jenkins unit test builds using docker.
#
# This script will build a docker container which will then be used to build
# and test the input UNIT_TEST_PKG. The docker container will be pre-populated
# with the most used OpenBMC repositories (phosphor-dbus-interfaces, sdbusplus,
# phosphor-logging, ...). This allows the use of docker caching
# capabilities so the dependent repositories are only built once per update
# to their corresponding repository. If a BRANCH parameter is input then the
# docker container will be pre-populated with the latest code from that input
# branch. If the branch does not exist in the repository, then master will be
# used.
#
#   UNIT_TEST_PKG:   Required, repository which has been extracted and is to
#                    be tested
#   WORKSPACE:       Required, location of unit test scripts and repository
#                    code to test
#   BRANCH:          Optional, branch to build from each of the
#                    openbmc repositories. default is master, which will be
#                    used if input branch not provided or not found
#   dbus_sys_config_file: Optional, with the default being
#                         `/usr/share/dbus-1/system.conf`
#   TEST_ONLY:       Optional, do not run analysis tools
#   NO_FORMAT_CODE:  Optional, do not run format-code.sh
#   NO_CPPCHECK:     Optional, do not run cppcheck
#   EXTRA_DOCKER_RUN_ARGS:  Optional, pass arguments to docker run
#   EXTRA_UNIT_TEST_ARGS:  Optional, pass arguments to unit-test.py
#   INTERACTIVE: Optional, run a bash shell instead of unit-test.py
#   http_proxy: Optional, run the container with proxy environment
#   NEEDS_HOSTFW_SRC: Optional, set to a non-empty value to clone hostfw-src
#                     and make it available inside the container. Automatically
#                     set when UNIT_TEST_PKG=hostfw-src.

# Trace bash processing. Set -e so when a step fails, we fail the build
set -uo pipefail

# Default variables
BRANCH=${BRANCH:-"master"}
DOCKER_WORKDIR="${DOCKER_WORKDIR:-$WORKSPACE}"
OBMC_BUILD_SCRIPTS="openbmc-build-scripts"
UNIT_TEST_SCRIPT_DIR="${DOCKER_WORKDIR}/${OBMC_BUILD_SCRIPTS}/scripts"
UNIT_TEST_PY="unit-test.py"
DBUS_UNIT_TEST_PY="dbus-unit-test.py"
TEST_ONLY="${TEST_ONLY:-}"
DBUS_SYS_CONFIG_FILE=${dbus_sys_config_file:-"/usr/share/dbus-1/system.conf"}
MAKEFLAGS="${MAKEFLAGS:-""}"
NO_FORMAT_CODE="${NO_FORMAT_CODE:-}"
NO_CPPCHECK="${NO_CPPCHECK:-}"
INTERACTIVE="${INTERACTIVE:-}"
http_proxy=${http_proxy:-}
NEEDS_HOSTFW_SRC="${NEEDS_HOSTFW_SRC:-}"

# Timestamp for job
echo "Unit test build started, $(date)"

# Check workspace, build scripts, and package to be unit tested exists
if [ ! -d "${WORKSPACE}" ]; then
    echo "Workspace(${WORKSPACE}) doesn't exist, exiting..."
    exit 1
fi
if [ ! -d "${WORKSPACE}/${OBMC_BUILD_SCRIPTS}" ]; then
    echo "Package(${OBMC_BUILD_SCRIPTS}) not found in ${WORKSPACE}, exiting..."
    exit 1
fi
# shellcheck disable=SC2153 # UNIT_TEST_PKG is not misspelled.
if [ ! -d "${WORKSPACE}/${UNIT_TEST_PKG}" ]; then
    echo "Package(${UNIT_TEST_PKG}) not found in ${WORKSPACE}, exiting..."
    exit 1
fi

# Configure docker build
cd "${WORKSPACE}"/${OBMC_BUILD_SCRIPTS}
echo "Building docker image with build-unit-test-docker"
# Export input env variables
export BRANCH
DOCKER_IMG_NAME=$(./scripts/build-unit-test-docker)
export DOCKER_IMG_NAME

# Clone hostfw-src on the host where ~/.ssh/ is available.
# Automatically required when testing hostfw-src itself.
if [ "${UNIT_TEST_PKG}" = "hostfw-src" ]; then
    NEEDS_HOSTFW_SRC=1
fi

HOSTFW_SRC_DIR=""
if [ -n "${NEEDS_HOSTFW_SRC}" ]; then
    if [ "${UNIT_TEST_PKG}" = "hostfw-src" ]; then
        echo "UNIT_TEST_PKG=hostfw-src, using existing ${WORKSPACE}/hostfw-src"
        HOSTFW_SRC_DIR="${WORKSPACE}/hostfw-src"
    else
        HOSTFW_SRC_DIR=$(mktemp -d)
        trap 'rm -rf "${HOSTFW_SRC_DIR}"' EXIT
        echo "Cloning hostfw-src into ${HOSTFW_SRC_DIR}"
        git clone git@github.ibm.com:open-power/hostfw-src.git \
            "${HOSTFW_SRC_DIR}" || \
            { echo "ERROR: Failed to clone hostfw-src. Ensure SSH key is configured for github.ibm.com."; exit 1; }
        # Check out the requested BRANCH if it exists in hostfw-src, mirroring the
        # revision-selection logic the old package mechanism used: match $BRANCH,
        # fall back to the default branch (master/main) if not found.
        if git -C "${HOSTFW_SRC_DIR}" ls-remote --heads origin "${BRANCH}" \
                | grep -q "${BRANCH}"; then
            git -C "${HOSTFW_SRC_DIR}" checkout "${BRANCH}"
        else
            echo "Branch '${BRANCH}' not found in hostfw-src, using default branch"
        fi
    fi
fi

# Allow the user to pass options through to unit-test.py:
#   EXTRA_UNIT_TEST_ARGS="-r 100" ...
EXTRA_UNIT_TEST_ARGS="${EXTRA_UNIT_TEST_ARGS:+,${EXTRA_UNIT_TEST_ARGS/ /,}}"

# Unit test and parameters
if [ "${INTERACTIVE}" ]; then
    UNIT_TEST="/bin/bash"
else
    UNIT_TEST_PKG_PATH="${UNIT_TEST_PKG}"
    # When testing hostfw-src itself, point unit-test.py at the phal subdirectory
    # which contains the meson.build — the hostfw-src root has no build system.
    if [ "${UNIT_TEST_PKG}" = "hostfw-src" ]; then
        UNIT_TEST_PKG_PATH="hostfw-src/phal"
    fi
    UNIT_TEST="${UNIT_TEST_SCRIPT_DIR}/${UNIT_TEST_PY},-w,${DOCKER_WORKDIR},\
-p,${UNIT_TEST_PKG_PATH},-b,$BRANCH,\
-v${TEST_ONLY:+,-t}${NO_FORMAT_CODE:+,-n}${NO_CPPCHECK:+,--no-cppcheck}\
${EXTRA_UNIT_TEST_ARGS}"
fi

# Run the docker unit test container with the unit test execution script
echo "Executing docker image"

PROXY_ENV=""
# Set up proxies
if [ -n "${http_proxy}" ]; then
    PROXY_ENV=" \
        --env HTTP_PROXY=${http_proxy} \
        --env HTTPS_PROXY=${http_proxy} \
        --env FTP_PROXY=${http_proxy} \
        --env http_proxy=${http_proxy} \
        --env https_proxy=${http_proxy} \
        --env ftp_proxy=${http_proxy}"
fi

# If we are building on a podman based machine, need to have this set in
# the env to allow the home mount to work (no impact on non-podman systems)
export PODMAN_USERNS="keep-id"

HOSTFW_VOLUME_ARG=""
HOSTFW_PRE_CMD=""
PHAL_PYTHONPATH=""
if [ -n "${NEEDS_HOSTFW_SRC}" ]; then
    # Prepare hostfw-src/phal inside the container before running tests.
    # The source was cloned on the host and is available via the workspace mount.
    PHAL_PYTHONPATH="${DOCKER_WORKDIR}/hostfw-src/ekb/public/common/generic/tools/sbe_tools/targeting"

    LIBFDT_PC_CONTENT="prefix=/usr\n\
libdir=\${prefix}/lib/x86_64-linux-gnu\n\
includedir=\${prefix}/include\n\
\n\
Name: libfdt\n\
Description: Flat Device Tree library\n\
Version: 0\n\
Libs: -L\${libdir} -lfdt\n\
Cflags: -I\${includedir}\n"

    HOSTFW_PREAMBLE="cd ${DOCKER_WORKDIR}/hostfw-src && \
pip3 install --break-system-packages --root-user-action=ignore networkx && \
sudo sh -c 'printf \"${LIBFDT_PC_CONTENT}\" > /usr/local/lib/pkgconfig/libfdt.pc' && \
cd ${DOCKER_WORKDIR} && "

    if [ "${UNIT_TEST_PKG}" = "hostfw-src" ]; then
        HOSTFW_PRE_CMD="${HOSTFW_PREAMBLE}"
    else
        HOSTFW_PRE_CMD="${HOSTFW_PREAMBLE}meson setup /tmp/hostfw-phal-builddir \
${DOCKER_WORKDIR}/hostfw-src/phal --prefix=/usr/local && \
ninja -C /tmp/hostfw-phal-builddir && \
sudo ninja -C /tmp/hostfw-phal-builddir install && \
sudo ldconfig && "
    fi

    HOSTFW_VOLUME_ARG="-v ${HOSTFW_SRC_DIR}:${DOCKER_WORKDIR}/hostfw-src"
fi

# shellcheck disable=SC2086 # ${PROXY_ENV}, ${EXTRA_DOCKER_RUN_ARGS}, and
# ${HOSTFW_VOLUME_ARG} are meant to be split
docker run --cap-add=sys_admin --rm=true \
    --privileged=true \
    ${PROXY_ENV} \
    -u "$USER" \
    -w "${DOCKER_WORKDIR}" -v "${HOME}:${HOME}" \
    -v "${WORKSPACE}":"${DOCKER_WORKDIR}" \
    ${HOSTFW_VOLUME_ARG} \
    -e "MAKEFLAGS=${MAKEFLAGS}" \
    -e "PYTHONPATH=${PHAL_PYTHONPATH}${PYTHONPATH:+:${PYTHONPATH}}" \
    ${EXTRA_DOCKER_RUN_ARGS:-} \
    -${INTERACTIVE:+i}t "${DOCKER_IMG_NAME}" \
    /bin/bash -c "${HOSTFW_PRE_CMD}\
    ${UNIT_TEST_SCRIPT_DIR}/${DBUS_UNIT_TEST_PY} -u ${UNIT_TEST} \
    -f ${DBUS_SYS_CONFIG_FILE}"

# Timestamp for build
echo "Unit test build completed, $(date)"
