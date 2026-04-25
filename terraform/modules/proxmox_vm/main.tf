resource "proxmox_vm_qemu" "vm" {
  name        = var.name
  vmid        = var.vmid
  target_nodes = [var.target_node]

  agent                  = 1
  bios                   = "seabios"
  boot                   = "order=scsi0;ide2;net0"
  define_connection_info = false
  force_create           = false
  full_clone             = false
  hotplug                = "network,disk,usb"
  kvm                    = true
  memory                 = var.memory
  qemu_os                = "l26"
  scsihw                 = "virtio-scsi-single"
  tablet                 = true
  tags                   = var.tags
  start_at_node_boot     = var.start_at_node_boot
  description            = <<-EOT
    ## ${var.name}

    - cpu : ${var.cores}core
    - mem : ${var.memory / 1024}GB
    - disk : ${var.disk_size}

    - docker installed
    - KST
    - rha6780.pem 으로 접근가능

    ${var.notes}
    Managed by Terraform.
  EOT

  cpu {
    cores   = var.cores
    sockets = var.sockets
    type    = var.cpu_type
    numa    = false
    limit   = 0
    units   = 0
    vcores  = 0
  }

  disks {
    ide {
      ide2 {
        cdrom {
          iso = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size               = var.disk_size
          storage            = var.storage
          format             = "raw"
          iothread           = true
          backup             = true
          replicate          = true
          discard            = false
          emulatessd         = false
          readonly           = false
          iops_r_burst         = 0
          iops_r_burst_length  = 0
          iops_r_concurrent    = 0
          iops_wr_burst        = 0
          iops_wr_burst_length = 0
          iops_wr_concurrent   = 0
          mbps_r_burst         = 0
          mbps_r_concurrent    = 0
          mbps_wr_burst        = 0
          mbps_wr_concurrent   = 0
        }
      }
    }
  }

  network {
    id        = 0
    bridge    = var.bridge
    model     = "virtio"
    macaddr   = var.macaddr
    firewall  = true
    link_down = false
    mtu       = 0
    queues    = 0
    rate      = 0
    tag       = 0
  }

  startup_shutdown {
    order            = -1
    shutdown_timeout = -1
    startup_delay    = -1
  }

  lifecycle {
    ignore_changes = [vm_state, tags]
  }
}
