#!/bin/bash
###############################################################################
#
# This script is for preparing the cppcheck repo environment for obmc-phosphor-image
#
###############################################################################
#
# Required Inputs:
#   WORKSPACE:  Directory which contains the extracted openbmc-build-scripts
#               directory
#   BRANCH:     Optional, branch or tag to build from each of the
#               openbmc repositories. default is master, which will be
#               used if input branch not provided or not found
#   REPOLIST:   List of repos to do the cppcheck.
#   MACHINE:    Type of system to run tests

usage()
{
    echo "Usage: setup-obmc-cppcheck.sh"
    echo "Example:"
    echo 'WORKSPACE=$(pwd) BRANCH=fw1120.00-1.70 ./openbmc-build-scripts/setup-obmc-cppcheck.sh '
    echo ""
}

# Default variables
BRANCH=${BRANCH:-""}
WORKSPACE=${WORKSPACE:-$(pwd)}
REPOLIST=${REPOLIST:-""}
OBMC_BUILD_SCRIPTS="openbmc-build-scripts"

#
REPOLIST=$(echo $REPOLIST)
#
[ -z "$BRANCH" ] && (usage; exit 1)

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

# Clone/Extract openbmc repo
function setup_openbmc_repos_for_cppcheck()
{
    cd ${WORKSPACE}
    if [ ! -d ./openbmc ]
    then
        echo git clone git@github.ibm.com:openbmc/openbmc.git
        git clone git@github.ibm.com:openbmc/openbmc.git
    fi

    cd ${WORKSPACE}/openbmc
    source setup ${MACHINE}

    ## fetch openbmc repo
    git fetch --all
    git checkout ${BRANCH}
    git pull

    # walk-thru each repo & prepare the cppcheck
    for REPONAME in ${REPOLIST}
    do
        echo "===== Extract repo $REPONAME and link to $WORKSPACE/$REPONAME ====="
        bitbake ${REPONAME} -f -c do_fetch
        bitbake ${REPONAME} -f -c do_unpack

        eval $(bitbake -e ${REPONAME} | grep ^WORKDIR=)
        if [ -d ${WORKDIR}/git ]
        then
            echo "Linking ${WORKDIR}/git to  $WORKSPACE/${REPONAME}"
            ln -fs ${WORKDIR}/git $WORKSPACE/${REPONAME}
        fi
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

echo "Usage:  setup-obmc-cppcheck.sh for branch ${BRANCH}"

setup_openbmc_repos_for_cppcheck

exit 0
