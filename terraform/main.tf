resource "proxmox_vm_qemu" "vm-iac-01" {
  name                   = "vm-iac-01"
  target_nodes              = [
          "pve-main",
  ]
  agent                  = 1
  args                   = null
  bios                   = "seabios"
  boot                   = "order=scsi0;ide2;net0"
  bootdisk               = null
  define_connection_info = false
  force_create           = false
  full_clone             = false
  hagroup                = null
  hastate                = null
  hotplug                = "network,disk,usb"
  kvm                    = true
  machine                = null
  memory                 = 2048
  pool                   = null
  qemu_os                = "l26"
  scsihw                 = "virtio-scsi-single"
  tablet                 = true
  tags                   = null
  vmid                   = 203
  start_at_node_boot        = true
  description            = <<-EOT
          ## vm-temp-01

          - cpu : 2core
          - mem : 2GB
          - disk : 20GB

          
          - docker installed
          - KST
          - rha6780.pem 으로 접근가능
          Managed by Terraform.
        EOT

  cpu {
    affinity = null
    cores    = 2
    limit    = 0
    numa     = false
    sockets  = 1
    type     = "x86-64-v2-AES"
    units    = 0
    vcores   = 0
  }

  disks {
        ide {
            ide2 {
                # ignore = false
                cdrom {
                    iso         = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
                }
            }
        }
        scsi {
            scsi0 {
                # ignore = false

                disk {
                    asyncio              = null
                    backup               = true
                    cache                = null
                    discard              = false
                    emulatessd           = false
                    format               = "raw"
                    # id                   = 0
                    iops_r_burst         = 0
                    iops_r_burst_length  = 0
                    iops_r_concurrent    = 0
                    iops_wr_burst        = 0
                    iops_wr_burst_length = 0
                    iops_wr_concurrent   = 0
                    iothread             = true
                    # linked_disk_id       = -1
                    mbps_r_burst         = 0
                    mbps_r_concurrent    = 0
                    mbps_wr_burst        = 0
                    mbps_wr_concurrent   = 0
                    readonly             = false
                    replicate            = true
                    serial               = null
                    size                 = "20G"
                    storage              = "local-lvm"
                    wwn                  = null
                }
            }
        }
    }
  network {
    id        = 0
    bridge    = "vmbr0"
    firewall  = true
    link_down = false
    macaddr   = "bc:24:11:36:e2:1f"
    model     = "virtio"
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

}