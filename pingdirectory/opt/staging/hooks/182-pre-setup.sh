#!/usr/bin/env sh
#
# Ping Identity DevOps - Docker Build Hooks
#
${VERBOSE} && set -x

# shellcheck source=../../../../pingcommon/opt/staging/hooks/pingcommon.lib.sh
. "${HOOKS_DIR}/pingcommon.lib.sh"

# shellcheck source=../../../../pingdatacommon/opt/staging/hooks/pingdata.lib.sh
test -f "${HOOKS_DIR}/pingdata.lib.sh" && . "${HOOKS_DIR}/pingdata.lib.sh"

#
# If we are:
#  - kubernetes
#  - version 8.2 or greater
#  - no IP is found for the $_podHostname
# then
#  This implies that a headless service allowing for unready hosts isn't setup which is
#  required to ensure that the pingdirectory service isn't available until after all the
#  required replication has been setup.  If we don't check for this here then the
#  setup process here will fail.
if test "${ORCHESTRATION_TYPE}" = "KUBERNETES" &&
   test "$( isImageVersionGtEq 8.2.0 )" -eq 0 &&
   test -z "$( getIP "${_podHostname}" )"
then
    echo_red "Detected:"
    echo_red "  - Container running in Kubernetes"
    echo_red "  - Running version 8.2 or higher"
    echo_red "  - The Kubernetes service providing IP for '${_podHostname}' isn't returning any value"
    echo_red ""
    echo_red "This implies that the Kubernetes service isn't providing the annotations allowing for"
    echo_red "unready hosts to be discovered."
    echo_red ""
    echo_red "RESOLUTION - Create/Add a separate cluster service with the following annotations/spec"
    echo_red ""
    echo_red "  metadata:"
    echo_red "    annotations:"
    echo_red "      service.alpha.kubernetes.io/tolerate-unready-endpoints: true"
    echo_red "  spec:"
    echo_red "    publishNotReadyAddresses: true"
    echo_red ""

    container_failure 182 "Resolve issues with pingdirectory Kubernetes cluster service, and restart"
fi

#
# If we are the GENESIS state, then process any templates if they are defined.
#
if test "${PD_STATE}" = "GENESIS" ;
then
    echo "PD_STATE is GENESIS ==> Processing Templates"

    # TODO need to process all ldif subdirectories, not just userRoot
    LDIF_DIR="${PD_PROFILE}/ldif/userRoot"
    TEMPLATE_DIR="${LDIF_DIR}"
    test -z "${MAKELDIF_USERS}" && MAKELDIF_USERS=0

    # FIXME: this will break for file names with whitespaces
    for template in $( find "${TEMPLATE_DIR}" -type f -iname \*.template 2>/dev/null ) ;
    do
            echo "Processing (${template}) template with ${MAKELDIF_USERS} users..."
            GENERATED_LDIF_FILENAME="${template%.*}.ldif"
            "${SERVER_ROOT_DIR}/bin/make-ldif" \
                --templateFile "${template}"  \
                --ldifFile "${GENERATED_LDIF_FILENAME}" \
                --numThreads 3

            # Add the generated ldif file to the profile's variables-ignore.txt file, to avoid
            # the potential memory overhead of variable substitution on a large file.
            GENERATED_LDIF_BASENAME=$( basename "${GENERATED_LDIF_FILENAME}" )
            echo "ldif/userRoot/${GENERATED_LDIF_BASENAME}" >> "${PD_PROFILE}/variables-ignore.txt"
    done
else
    echo "PD_STATE is not GENESIS ==> Skipping Templates"
    echo "PD_STATE is not GENESIS ==> Will not process ldif imports"

    # GDO-191 - Following is used by 183-run-setup.sh.  Appended to CONTAINER_ENV, to allow for that
    # hook to pick it up
    _skipImports="--skipImportLdif"

    # next line is for shellcheck disable to ensure $RUN_PLAN is used
    echo "${_skipImports}" >> /dev/null

    export_container_env _skipImports
fi