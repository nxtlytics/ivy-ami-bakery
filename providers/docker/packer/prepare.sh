#!/usr/bin/env bash
set -xeuo pipefail
IFS=$'\n\t'

# Upgrade the base image fully
# TODO: discuss potentially disabling this after building base to prevent blindly sliding package versions from build to build
yum -y update

# Install dev tools and python
yum install -y wget python-rpm-macros python3-rpm python3-devel libffi libffi-devel openssl-devel python3-pip sudo
yum groupinstall -y 'Development Tools'

# ansible expects python at /usr/bin/python NOT at /bin/python
ln -s "$(command -v python3)" /usr/bin/python

# Allow notty sudo
sed -n -e '/Defaults.*requiretty/s/^/#/p' /etc/sudoers

# Upgrade pip
pip3 install --upgrade pip

# Install ansible
pip3 install --upgrade --trusted-host pypi.python.org ansible==5.4.0
