#!/bin/bash
#
# reload haproxy, but avoid losing existing connections
#
#  briefly reject connection (SYN) TCP packets during port switch, so that
#  connections are retried
#
# see:
#  https://medium.com/@Drew_Stokes/actual-zero-downtime-with-haproxy-18318578fde6
#  http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html
#
function get_drop_status() {
    iptables -L INPUT | grep -E '^DROP.*multiport dports http,(http-alt|webcache).*$'
}

function disable_http() {
    while [ -z "$(get_drop_status)" ]; do
        echo "Dropping incoming http(s) packets..."
        iptables -I INPUT -p tcp -m multiport --dports 80,8080 --syn -j DROP
    done
}

function reload_haproxy() {
    echo "$(date +%Y%m%d-%H:%M:%S.%N) PID: $$ - Reloading haproxy..."
    service haproxy reload
}

function enable_http() {
    while [ "$(get_drop_status)" ]; do
        echo "Enabling incoming http(s) packets..."
        iptables -D INPUT -p tcp -m multiport --dports 80,8080 --syn -j DROP
    done
}

disable_http
reload_haproxy

trap enable_http EXIT
