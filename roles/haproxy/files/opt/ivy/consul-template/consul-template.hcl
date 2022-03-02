consul = {
  address = "localhost:8500"
}

deduplicate {
  enabled = true
  prefix  = "consul-template/dedup/"
}

max_stale = "5s"
wait = "10s:60s"

template {
  source = "/opt/ivy/consul-template/tpl/blocked_ips.tmpl"
  destination = "/etc/haproxy/blocked_ips.txt"
}

template {
  source = "/opt/ivy/consul-template/tpl/mesos-slave-haproxy.cfg.tmpl"
  destination = "/etc/haproxy/haproxy.cfg"
  command = "/opt/ivy/consul-template/reload_haproxy.sh"
}
