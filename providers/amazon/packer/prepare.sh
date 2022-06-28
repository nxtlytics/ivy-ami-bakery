#!/usr/bin/env bash
set -x
# Allow notty sudo
sed -n -e '/Defaults.*requiretty/s/^/#/p' /etc/sudoers
# install python 3.8
yum install -y amazon-linux-extras
amazon-linux-extras enable python3.8
# Upgrade the base image fully
# TODO: discuss potentially disabling this after building base to prevent blindly sliding package versions from build to build
yum -y update
# Install dev tools and python
yum install -y wget libffi libffi-devel openssl-devel python3.8
yum groupinstall -y 'Development Tools'
# Upgrade pip
if [[ ! -f get-pip.py ]]; then
    wget https://bootstrap.pypa.io/get-pip.py && python3.8 get-pip.py
fi
# Install ansible
pip3 install --upgrade --trusted-host pypi.python.org ansible==5.6.0
