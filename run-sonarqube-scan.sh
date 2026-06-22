#!/bin/bash -xe

# This script is for running SonarQube scans on OpenBMC repositories using docker.
#
# This script will use a docker container with SonarQube scanner pre-installed
# to scan the repository code and send results to the SonarQube server.
#
# Required Parameters:
#   WORKSPACE:           Location of repository code to scan
#   SONARQUBE_URL:       URL of the SonarQube server
#   SONARQUBE_TOKEN:     Authentication token for SonarQube server
#   PROJECT_KEY:         SonarQube project key
#
# Optional Parameters:
#   PROJECT_NAME:        SonarQube project name (should be org/repo format)
#   GIT_PULL_NUMBER:     Pull request number for PR analysis
#   PROJECT_BRANCH:      Branch name for PR analysis
#   GIT_PULL_BASE:       Base branch for PR analysis
#   CERT_PATH:           Path to certificate file for HTTPS
#   CERT_PASSWORD:       Password for certificate
#   SONAR_SOURCES:       Source directories to scan (default: .)
#   EXTRA_SONAR_ARGS:    Additional arguments to pass to sonar-scanner
#   http_proxy:          HTTP proxy URL

# Trace bash processing. Set -e so when a step fails, we fail the build
set -uo pipefail

# Timestamp for job
echo "SonarQube scan started, $(date)"

# Required parameters
if [ -z "${WORKSPACE:-}" ]; then
    echo "WORKSPACE is not set, exiting..."
    exit 1
fi

if [ -z "${SONARQUBE_URL:-}" ]; then
    echo "SONARQUBE_URL is not set, exiting..."
    exit 1
fi

if [ -z "${SONARQUBE_TOKEN:-}" ]; then
    echo "SONARQUBE_TOKEN is not set, exiting..."
    exit 1
fi

if [ -z "${PROJECT_KEY:-}" ]; then
    echo "PROJECT_KEY is not set, exiting..."
    exit 1
fi

# Optional parameters with defaults
# PROJECT_NAME should be set to org/repo format, not defaulting to PROJECT_KEY
if [ -z "${PROJECT_NAME:-}" ]; then
    echo "PROJECT_NAME is not set. It should be in format: org/repo"
    echo "Example: export PROJECT_NAME=\"openbmc/ibm-power-highend-platform-apps\""
    exit 1
fi
SONAR_SOURCES="${SONAR_SOURCES:-.}"
DOCKER_IMG_NAME="${DOCKER_IMG_NAME:-sonarsource/sonar-scanner-cli}"
http_proxy=${http_proxy:-}

# Check workspace exists
if [ ! -d "${WORKSPACE}" ]; then
    echo "Workspace(${WORKSPACE}) doesn't exist, exiting..."
    exit 1
fi

# Build sonar-scanner command
SONAR_CMD="sonar-scanner"
SONAR_CMD="${SONAR_CMD} -Dsonar.projectKey=${PROJECT_KEY}"
SONAR_CMD="${SONAR_CMD} -Dsonar.projectName=\"${PROJECT_NAME}\""
SONAR_CMD="${SONAR_CMD} -Dsonar.sources=${SONAR_SOURCES}"
SONAR_CMD="${SONAR_CMD} -Dsonar.host.url=${SONARQUBE_URL}"
SONAR_CMD="${SONAR_CMD} -Dsonar.token=${SONARQUBE_TOKEN}"

# Add PR-specific parameters if provided
if [ -n "${GIT_PULL_NUMBER:-}" ]; then
    SONAR_CMD="${SONAR_CMD} -Dsonar.pullrequest.key=${GIT_PULL_NUMBER}"
fi

if [ -n "${PROJECT_BRANCH:-}" ]; then
    SONAR_CMD="${SONAR_CMD} -Dsonar.pullrequest.branch=${PROJECT_BRANCH}"
fi

if [ -n "${GIT_PULL_BASE:-}" ]; then
    SONAR_CMD="${SONAR_CMD} -Dsonar.pullrequest.base=${GIT_PULL_BASE}"
fi

# Add certificate parameters if provided
CERT_MOUNT=""
if [ -n "${CERT_PATH:-}" ]; then
    if [ ! -f "${CERT_PATH}" ]; then
        echo "Certificate file ${CERT_PATH} not found, exiting..."
        exit 1
    fi
    # Mount certificate into /usr/src (working directory) to match working script
    CERT_MOUNT="-v ${CERT_PATH}:/usr/src/castorevpcprod"
    SONAR_CMD="${SONAR_CMD} -Dsonar.scanner.truststorePath=/usr/src/castorevpcprod"
    
    if [ -n "${CERT_PASSWORD:-}" ]; then
        SONAR_CMD="${SONAR_CMD} -Dsonar.scanner.truststorePassword=${CERT_PASSWORD}"
    fi
fi

# Add any extra arguments
if [ -n "${EXTRA_SONAR_ARGS:-}" ]; then
    SONAR_CMD="${SONAR_CMD} ${EXTRA_SONAR_ARGS}"
fi

# Set up proxy environment variables
PROXY_ENV=""
if [ -n "${http_proxy}" ]; then
    PROXY_ENV=" \
        --env HTTP_PROXY=${http_proxy} \
        --env HTTPS_PROXY=${http_proxy} \
        --env http_proxy=${http_proxy} \
        --env https_proxy=${http_proxy}"
fi

# If we are building on a podman based machine, need to have this set in
# the env to allow the home mount to work (no impact on non-podman systems)
export PODMAN_USERNS="keep-id"

echo "Running SonarQube scan with command:"
echo "${SONAR_CMD}"

# Run the docker container with sonar-scanner
# shellcheck disable=SC2086 # ${PROXY_ENV} and ${CERT_MOUNT} are meant to be split
docker run --rm=true \
    ${PROXY_ENV} \
    -e SONAR_HOST_URL="${SONARQUBE_URL}" \
    -e SONAR_TOKEN="${SONARQUBE_TOKEN}" \
    -v "${WORKSPACE}:/usr/src" \
    ${CERT_MOUNT} \
    "${DOCKER_IMG_NAME}" \
    ${SONAR_CMD}

# Timestamp for completion
echo "SonarQube scan completed, $(date)"

# Made with Bob
