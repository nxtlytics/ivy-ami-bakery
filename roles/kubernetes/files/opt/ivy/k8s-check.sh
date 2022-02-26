#!/bin/bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
. /opt/ivy/bash_functions.sh


THIS_SCRIPT=$(basename "${0}")
PADDING=$(printf %-${#THIS_SCRIPT}s " ")

function usage () {
  echo "Usage:"
  echo "${THIS_SCRIPT} -a,--ask-to-continue <Set this flag to ask before running next check>"
  echo "${PADDING} -e, --explain <Set this flag to print all checks explanations>"
  echo "${PADDING} -s, --stack-name <Name of the stack this instance is a part of>"
  echo
  echo "Runs checks for a given stack name, used to know if a given instance was properly configured or not"
  exit
}

ASK='no'
EXPLAIN='no'
while [[ $# -gt 0 ]]; do
  case "${1}" in
      -a|--ask-to-continue)
        ASK='yes'
        shift # past argument
        ;;
      -e|--explain)
        EXPLAIN='yes'
        shift # past argument
        ;;
      -s|--stack-name)
        STACK_NAME="${2}"
        shift # past argument
        shift # past value
        ;;
      -*)
        echo "Unknown option ${1}"
        usage
        ;;
  esac
done

if [[ -z ${STACK_NAME:-""} ]] ; then
  usage
fi

warn 'Always check: /var/log/cloud-init*'
warn 'You may run: tail -F /var/log/cloud-init*'

if [[ "${STACK_NAME}" == 'k8s-controllers' ]]; then
  k8s_controller_checks "${EXPLAIN}" "${ASK}"
fi

if [[ "${STACK_NAME}" =~ ^k8s.* ]]; then
  k8s_checks "${EXPLAIN}" "${ASK}"
fi
