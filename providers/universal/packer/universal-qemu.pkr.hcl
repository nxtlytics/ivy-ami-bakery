variable "provider_name" {
  type        = string
  description = "Name of the provider, used for building paths and enabling provider-specific logic"
}

variable "ivy_tag" {
  type        = string
  default     = "ivy"
  description = "Tag prefix to use for all tag-related functions in the built image. Can be overridden with `set_ivy_tag` bash function"
}

variable "image_name" {
  type        = string
  description = "Image to build. Must exist in 'providers/<provider_name>/images"
}

variable "base_image" {
  type        = string
  description = "Base image to build from"
}

variable "base_image_checksum" {
  type        = string
  description = "Base image checksum (can be `md5:...`, or `sha1:...`)"
}

variable "qemu_accelerator" {
  type        = string
  description = "QEMU accelerator to use"
}

variable "vm_name" {
  type        = string
  description = "VM name for the builder"
}

variable "ssh_username" {
  type        = string
  description = "SSH username for connecting to the target"
}

variable "ssh_key_file" {
  type        = string
  description = "SSH private key file"
}

variable "tmp_dir" {
  type        = string
  description = "Path to temporary directory used for cloud-init data and ssh keypair"
}

locals {
  # Path relative to entrypoint (build.sh) where this provider stores its files
  provider_dir = "./providers/${var.provider_name}"
}

source "qemu" "builder" {
  iso_url      = var.base_image
  iso_checksum = var.base_image_checksum
  # This iso is actually a qcow image
  disk_image       = true
  output_directory = "out"

  vm_name = var.vm_name
  //  disk_size = "5000M"
  format = "qcow2"

  // 2 cores and 2gb ram should be enough for provisioning anything, right?
  cpus        = 2
  memory      = 2048
  accelerator = var.qemu_accelerator

  ssh_username              = var.ssh_username
  ssh_private_key_file      = var.ssh_key_file
  ssh_clear_authorized_keys = true
  ssh_timeout               = "20m"
  ssh_handshake_attempts    = 100

  //  net_device        = "virtio-net"
  //  disk_interface    = "virtio"
  //  boot_wait         = "10s"

  display  = ""
  headless = true

  cd_files = ["${var.tmp_dir}/meta-data", "${var.tmp_dir}/user-data"]
  cd_label = "cidata"

  qemuargs = [
    ["-serial", "stdio"],
    ["-netdev", "user,hostfwd=tcp::{{ .SSHHostPort }}-:22,id=forward"],
    ["-device", "virtio-net,netdev=forward,id=net0"]
  ]

}

build {
  sources = ["source.qemu.builder"]

  provisioner "shell" {
    # download the prerequisites for running ansible and some other niceties
    script = "${local.provider_dir}/packer/prepare.sh"
    # run command as root
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "ansible-local" {
    # provision the machine with the given role
    playbook_file = "${local.provider_dir}/images/${var.image_name}/provision.yml"
    playbook_dir  = "./roles"
    //    extra_arguments = [
    //      "--extra-vars \"ivy_tag={{user `ivy_tag`}} enable_azure_compat={{user `enable_azure_compat`}}\""
    //    ]
    clean_staging_directory = true
  }

  provisioner "shell" {
    # generalize the machine after it is finished provisioning
    inline = [
      "cloud-init clean -f"
    ]
    # run command as root
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  //  post-processor "shell-local" {
  //    inline = ["echo Hello World from ${source.type}.${source.name}"]
  //  }
  //
  //  post-processor "amazon-import" {
  //    # Export the image to AWS
  //    # needs permissions from: https://www.packer.io/plugins/post-processors/amazon#amazon-permissions
  //    # TODO: need to figure out how to clone ami to rename it, and share it to the appropriate users
  //    region         = "us-east-1"
  //    s3_bucket_name = "importbucket"
  //    license_type   = "BYOL"
  //    tags {
  //      Description = "packer amazon-import {{timestamp}}"
  //    }
  //  }
  //  post-processor "shell-local" {
  //    # Export the image to Azure
  //    script = "./azure-copy.sh ${output}"
  //  }

  //  post-processor "shell-local" {
  //    # remove the temp dir containing the cloud-init data and temporary ssh key
  //    inline = "rm -rf ${var.tmp_dir}"
  //  }

}