#!/bin/bash -x

# Allow notty sudo
sed -n -e '/Defaults.*requiretty/s/^/#/p' /etc/sudoers

# Upgrade the base image fully
# TODO: discuss potentially disabling this after building base to prevent blindly sliding package versions from build to build
yum -y update

# Install dev tools and python
yum install -y wget python3-devel libffi libffi-devel openssl-devel python3-pip
yum groupinstall -y 'Development Tools'

# Upgrade pip
if [[ ! -f get-pip.py ]]; then
    wget https://bootstrap.pypa.io/get-pip.py && python3 get-pip.py
fi

# Install ansible
pip3 install --upgrade --trusted-host pypi.python.org ansible==2.10.0
