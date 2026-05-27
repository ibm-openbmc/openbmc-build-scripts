#!/bin/bash
#
# Test for cppcheck filter
# Required Inputs:
#   WORKSPACE:    Directory which contains the extracted openbmc-build-scripts
#                  directory
#   REPONAME:    repo to run cppcheck.  If not, use UNIT_TEST_PKG
#   LOGDIR:      Optional, log output dir. If not, WORKSPACE/logs/
#   REPORTDIR:   Optional, report output dir, If not, use WORKSPACE/reports/

set -uo pipefail

args=$*

[ -z "${UNIT_TEST_PKG}" ] && ( echo "UNIT_TEST_PKG is not set"; exit 1)

WORKSPACE=${WORKSPACE:-$(pwd)}
REPONAME=${REPONAME:-${UNIT_TEST_PKG}}
LOGDIR=${LOGDIR:-${WORKSPACE}/logs}
REPORTDIR=${REPORTDIR:-${WORKSPACE}/reports}
mkdir -p ${LOGDIR}
mkdir -p ${REPORTDIR}

## Note: Additional necessary opts
CPPCHECK_ADD_OPTS=-D"__cppcheck__=1"

CPPCHECK_STDOUT=${LOGDIR}/cppchk.${REPONAME}.stdout
CPPCHECK_STDERR=${LOGDIR}/cppchk.${REPONAME}.stderr
cppcheck ${CPPCHECK_ADD_OPTS}  --template="{file}:{line}:{column}: {id}: {severity}: {message}" $args  2> ${CPPCHECK_STDERR} | tee ${CPPCHECK_STDOUT}

CPPCHECK_ERR_LOG=${REPORTDIR}/cppchk.${REPONAME}.error.log

FAILED=0

rm -f ${CPPCHECK_ERR_LOG}
while read -r filelinecol id severity remaining; do
    if [[ "$filelinecol" == "/"* || "$filelinecol" == "subprojects/"* ]]
    then
        # ignore the absolute-full-file paths like /usr/include/*, or under subprojects
        continue
    fi
    if [[ "$severity" == "warning:" || "$severity" == "error:" ]]
    then
        echo "Filename:Line:Column: $filelinecol" >> ${CPPCHECK_ERR_LOG}
        echo "id:severity: $id $severity" >> ${CPPCHECK_ERR_LOG}
        echo "remaining: $remaining" >> ${CPPCHECK_ERR_LOG}
        echo "---" >> ${CPPCHECK_ERR_LOG}
        FAILED=1
    fi
done < ${CPPCHECK_STDERR}

if [[ $FAILED -ne 0 ]]
then
	echo "cppcheck ($UNIT_TEST_PKG) failed, CPPCHECK_ERR_LOG=$CPPCHECK_ERR_LOG"
	cat ${CPPCHECK_ERR_LOG}
	exit 1
fi
