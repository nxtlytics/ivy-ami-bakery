#!/usr/bin/env bash
set -x
# grow partition
sudo lsblk
sudo xfs_growfs -d /
# print disk info
sudo df -Th
# Allow notty sudo
sudo sed -n -e '/Defaults.*requiretty/s/^/#/p' /etc/sudoers
# install python 3.8
sudo yum install -y amazon-linux-extras
sudo amazon-linux-extras enable python3.8
# Upgrade the base image fully
# TODO: discuss potentially disabling this after building base to prevent blindly sliding package versions from build to build
sudo yum -y update
# Install dev tools and python
sudo yum install -y wget libffi libffi-devel openssl-devel python3.8
sudo yum groupinstall -y 'Development Tools'
# Upgrade pip
if [[ ! -f get-pip.py ]]; then
    wget https://bootstrap.pypa.io/get-pip.py && python3.8 get-pip.py
fi
# Install ansible
sudo python3.8 -m pip install --upgrade --trusted-host pypi.python.org ansible==5.6.0
