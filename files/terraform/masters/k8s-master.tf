# variables that can be overriden
variable "hostname" { default = "k8s-master" }
variable "domain" { default = "k8s.lab" }
variable "memory" { default = 6 }
variable "cpu" { default = 3 }
variable "vm_count" { default = 2 }
variable "vm_volume_size" { default = 10 }
variable "iface" { default = "eth0" }
variable "libvirt_network" { default = "k8s" }
variable "libvirt_pool" { default= "k8s" }

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

# fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "os_image" {
  count = var.vm_count
  name = "${var.hostname}-os_image-${count.index}"
  pool = var.libvirt_pool
  source = "/tmp/CentOS-7-x86_64-GenericCloud-master.qcow2"
  #source = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "storage_image" {
  count = var.vm_count
  name = "${var.hostname}-${count.index}-storage_image"
  pool = var.libvirt_pool
  size = var.vm_volume_size*1073741824
  format = "qcow2"
}

# Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.vm_count
  name = "${var.hostname}-${count.index}-commoninit.iso"
  pool = var.libvirt_pool 
  user_data = data.template_file.user_data[count.index].rendered
  meta_data = data.template_file.meta_data[count.index].rendered
}


data "template_file" "user_data" {
  count = var.vm_count
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${var.hostname}-${count.index}.${var.domain}"
    fqdn = "${var.hostname}-${count.index}.${var.domain}"
    iface = var.iface
   }
}

#Fix for centOS
data "template_file" "meta_data" {
  template = file("${path.module}/network_config.cfg")
  count = var.vm_count
  vars = {
    hostname = "${var.hostname}-${count.index}.${var.domain}"
    iface = var.iface
  }
}


# Create the machine
resource "libvirt_domain" "k8s-master" {
  # domain name in libvirt, not hostname
  count= var.vm_count
  name = "${var.hostname}-${count.index}"
  memory = var.memory*1024
  vcpu = var.cpu

  disk {
     volume_id = libvirt_volume.os_image[count.index].id
  }

  disk {
     volume_id = libvirt_volume.storage_image[count.index].id
  }

  network_interface {
       network_name = var.libvirt_network
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = "true"
  }
}

terraform { 
  required_version = ">= 0.12"
}

output "ips" {
  value = "${flatten(libvirt_domain.k8s-master.*.network_interface.0.addresses)}"
}

output "macs" {
  value = "${flatten(libvirt_domain.k8s-master.*.network_interface.0.mac)}"
}
