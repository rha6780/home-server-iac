moved {
  from = module.k8s_vms["vm-dev-haproxy-01"]
  to   = module.kubernetes.module.vms["vm-dev-haproxy-01"]
}

moved {
  from = module.k8s_vms["vm-dev-k8s-cp-01"]
  to   = module.kubernetes.module.vms["vm-dev-k8s-cp-01"]
}

moved {
  from = module.k8s_vms["vm-dev-k8s-cp-02"]
  to   = module.kubernetes.module.vms["vm-dev-k8s-cp-02"]
}

moved {
  from = module.k8s_vms["vm-dev-k8s-wk-01"]
  to   = module.kubernetes.module.vms["vm-dev-k8s-wk-01"]
}

moved {
  from = module.k8s_vms["vm-dev-k8s-wk-02"]
  to   = module.kubernetes.module.vms["vm-dev-k8s-wk-02"]
}
