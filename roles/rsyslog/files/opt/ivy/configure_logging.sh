#!/bin/bash

# This script configures logging
# Use like:
# /opt/ivy/configure_logging.sh --mode redis --server log.mysysenv.mydomain.com
# /opt/ivy/configure_logging.sh --mode relp --server 10.24.240.2
# /opt/ivy/configure_logging.sh --mode redis --server-ssm-param /Infrastructure/Common/Logging
# /opt/ivy/configure_logging.sh --mode tcp --server myserver.abc.net
# /opt/ivy/configure_logging.sh --mode udp --server-tag <...>

# We should configure logging from the following sources:
# - system logging
# - container logs (?)
# -