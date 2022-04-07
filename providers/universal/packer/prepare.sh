#!/usr/bin/env bash
set -x
set -e

echo "Start prepare script"
echo "Meminfo:"
free -m
echo "Cpuinfo:"
cat /proc/cpuinfo

# Allow notty sudo
sed -n -e '/Defaults.*requiretty/s/^/#/p' /etc/sudoers

echo "Installing required packages"
dnf install -y wget libffi python3-pip
pip3 install --upgrade --trusted-host pypi.python.org ansible==5.4.0
