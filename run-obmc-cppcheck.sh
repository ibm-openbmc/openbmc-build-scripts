#!/bin/bash
###############################################################################
#
# This script is for running  the cppcheck for obmc-phosphor-image
#
###############################################################################
#
# Required Inputs:
#   WORKSPACE:  Directory which contains the extracted openbmc-build-scripts
#               directory
#   REPOLIST:   List of repos to do the cppcheck.

usage()
{
	echo "usage: run-obmc-cppcheck.sh <opt>"
    echo "Example:"
    echo 'WORKSPACE=$(pwd) openbmc-build-scripts/run-obmc-cppcheck.sh '
    echo ""
}

# Default variables
WORKSPACE=${WORKSPACE:-$(pwd)}
REPOLIST=${REPOLIST:-""}
OBMC_BUILD_SCRIPTS="openbmc-build-scripts"

#
REPOLIST=$(echo $REPOLIST)
#

# Check workspace, build scripts, and package to be unit tested exists
if [ ! -d "${WORKSPACE}" ]; then
    echo "Workspace(${WORKSPACE}) doesn't exist, exiting..."
    exit 1
fi
if [ ! -d "${WORKSPACE}/${OBMC_BUILD_SCRIPTS}" ]; then
    echo "Package(${OBMC_BUILD_SCRIPTS}) not found in ${WORKSPACE}, exiting..."
    exit 1
fi

##

# run cppcheck
function run_cppcheck()
{
    cd ${WORKSPACE}
    for REPONAME in ${REPOLIST}
    do
        UNIT_TEST_PKG=$REPONAME CPPCHECK_ONLY=1 ./openbmc-build-scripts/run-unit-test-docker.sh
    done
}


### MAIN ####


# MACHINE
MACHINE=${MACHINE:-p10bmc}
export MACHINE

# environment variables
#
# List of Repos to scan.
REPOLIST=${REPOLIST:-""}

# Check the repolist config file
REPOLIST_FILE=${WORKSPACE}/obmc-cppcheck-repolist.txt
[[ -z "${REPOLIST}" && -f "${REPOLIST_FILE}" ]] && REPOLIST=$(cat ${REPOLIST_FILE})

# Use default repos if not passed
if [ -z "${REPOLIST}" ]
then
   REPOLIST="
        bmcweb \
        dbus-sensors \
        entity-manager \
        ibm-acf \
        ipl \
        libpldm \
        obmc-console \
        openpower-debug-collector \
        openpower-hw-diags \
        openpower-hw-isolation \
        openpower-occ-control \
        openpower-vpd-parser \
        panel \
        phosphor-bmc-code-mgmt \
        phosphor-certificate-manager \
        phosphor-dbus-interfaces \
        phosphor-debug-collector \
        phosphor-host-ipmid \
        phosphor-inventory-manager \
        phosphor-led-manager \
        phosphor-logging \
        phosphor-power \
        phosphor-state-manager \
        phosphor-user-manager \
        pldm \
        powervm-handler \
        service-config-manager \
        telemetry \
        "
fi

echo "usage:  run-obmc-cppcheck.sh"


#
cd ${WORKSPACE}/openbmc
. setup ${MACHINE}

cd ${WORKSPACE}
run_cppcheck

exit 0
