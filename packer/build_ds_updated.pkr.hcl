#as of right now, not planning to hang on to previous versions of this. add a timestamp to name if I want an image history.

packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "source_image_family" {
  type    = string
  default = "nmfs-ubuntu-22-04"
}

#packer build build_ds.pkr.hcl

#this time, specify oslogin and iap for ssh
source "googlecompute" "build-image-ds" {
  project_id               = "ggn-nmfs-pamdata-prod-1"
  use_os_login             = true
  use_iap                  = true
  ssh_username             = "root"
  source_image_project_id  = ["nmfs-trusted-images"]
  source_image_family      = var.source_image_family
  zone                     = "us-east4-c"
  subnetwork               = "app-subnet1"
  omit_external_ip         = true
  use_internal_ip          = true
  network_project_id       = "ggn-nmfs-pamdata-prod-1"
  image_description        = "server for docker development from NMFS hardened Ubuntu image"
  #turn off secuture boot for gpu applications.
  enable_secure_boot       = true
  enable_integrity_monitoring = true
  enable_vtpm              = true
  disk_size                = 30
  image_family             = "pamdata-ds-gi"
  image_name               = "pamdata-docker-server"
}

build {
  sources = ["sources.googlecompute.build-image-ds"]

  #dormant friendy patching file config
  provisioner "shell" {
    inline        = ["mkdir ./temp"]
    remote_folder = "."
  }

  #dormant friendy patching file config
  provisioner "file" {
    source      = "./patching/"
    destination = "temp/"
  }

  #dormant friendy patching file config
  provisioner "file" {
    source      = "./patching/dormant_auto_off.sh"
    destination = "temp/dormant_auto_off.sh"
  }

  #dormant friendy patching file config
  provisioner "shell" {
    inline = [
      "sudo rm -r -f /root/dormant_friendly_patching_auto_off",
      "sudo mv ./temp /root/dormant_friendly_patching_auto_off"
    ]
    remote_folder = "."
  }

  #configure patching window auto-shutdown behavior.
  provisioner "shell" {
    inline = [
      "sudo chmod +x /root/dormant_friendly_patching_auto_off/dormant_auto_off.sh",
      "sudo echo @reboot root /root/dormant_friendly_patching_auto_off/dormant_auto_off.sh | sudo tee /etc/cron.d/runscript"
    ]
    remote_folder = "."
  }

 ###### install docker engine: instructions for ubuntu. from https://docs.docker.com/engine/install/ubuntu/

  provisioner "shell" {
    script        = "./patching/update_and_upgrade.sh"
    remote_folder = "."
  }

  # Add Docker's official GPG key:
  provisioner "shell" {
    script        = "./docker_server_scripts/official_docker_key_add.sh"
    remote_folder = "."
  }

  # Add the repository to Apt sources:
  # this uses a lot of internal quotes, so I am running as it's own script.
  provisioner "shell" {
    script        = "./docker_server_scripts/add_repo_to_apt.sh"
    remote_folder = "."
  }

  # CIS 1.2.2: Ensure that the version of docker is up to date
  # satisfied here, and satisfied by base AFSC CI image update weekly schedule.
  provisioner "shell" {
    script        = "./docker_server_scripts/install_docker_latest.sh"
    remote_folder = "."
  }
  
  ######## CIS benchmarks *******

  #Total exceptions recommended:
  #1.1.1: create partition for docker mount point.
  ### preventatively technically difficult/clunky

  #2.12: Ensure that authorization for Docker client commands is enabled
  ### not yet mature enough on admin side to define custom policy

  #2.13: Ensure centralized and remote logging is configured
  ### more of an organizational challenge than specific to this server

  #2.17: Ensure that a daemon-wide custom seccomp profile is applied if appropriate
  ### not yet mature enough on admin side to define custom policy

  #Still to address:
  #5.30 Ensure that Docker's default bridge "docker0" is not used
  ### gets into networking, will be addressed and evaluated in app testing.

  #All CIS benchmarks addressed in order.

  #CIS 1.1.1: create partition for docker mount point.
  ##recommend exemption- doesn't work well starting with a 100% allocated disk. attaching a disk
  #complicates deployment by quite a bit. Will be user responsibility not to fill it up,
  #as with other machines.

  #CIS 1.1.2: Ensure only trusted users are allowed to control Docker daemon (Manual)
  #new install, so not relevant.

  #CIS 1.1.3: Add auditing rule to docker daemon
  #CIS 1.1.4: Add auditing rule to containerd
  #CIS 1.1.5: Add auditing rule to /var/lib/docker
  #CIS 1.1.6: Add auditing rule to /etc/docker
  #CIS 1.1.7: Add auditing rule to docker.service
  #CIS 1.1.8: Add auditing rule to containerd.sock
  #CIS 1.1.9: Add auditing rule to docker.socket
  #CIS 1.1.10: Add auditing rule to /etc/default/docker
  #CIS 1.1.11: Add auditing rule to /etc/docker/daemon.json
  #CIS 1.1.12: Add auditing rule to /etc/containerd/config.toml
  #CIS 1.1.13: Add auditing rule to /etc/sysconfig/docker
  #CIS 1.1.14: Add auditing rule to /usr/bin/containerd
  #CIS 1.1.15: Add auditing rule to /usr/bin/containerd-shim
  #CIS 1.1.16: Add auditing rule to /usr/bin/containerd-shim-runc-v1
  #CIS 1.1.17: Add auditing rule to /usr/bin/containerd-shim-runc-v2
  #CIS 1.1.18: Add auditing rule to /usr/bin/runc

  provisioner "shell" {
    inline = [
      "echo -w /usr/bin/dockerd -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -a exit,always -F path=/run/containerd -F perm=war -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -a exit,always -F path=/var/lib/docker -F perm=war -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /etc/docker -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /lib/systemd/system/docker.service -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /run/containerd/containerd.sock -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /lib/systemd/system/docker.socket -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /etc/default/docker -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /etc/docker/daemon.json -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /etc/containerd/config.toml -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /etc/sysconfig/docker -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /usr/bin/containerd -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /usr/bin/containerd-shim -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /usr/bin/containerd-shim-runc-v1 -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /usr/bin/containerd-shim-runc-v2 -k docker | sudo tee -a /etc/audit/rules.d/audit.rules",
      "echo -w /usr/bin/runc -k docker | sudo tee -a /etc/audit/rules.d/audit.rules"
    ]
    remote_folder = "."
  }

  #CIS 1.2.1: Ensure the container host has been Hardened (Manual)
  #derives from NMFS hardened Ubuntu image = Hardened.

  #CIS 1.2.2: Ensure that the version of Docker is up to date (Manual)
  #satisfied earlier during install step and with patching schedule

  #CIS 2.1: Run the Docker daemon as a non-root user, if possible:
  #holding off on configuring this- may not be possible with the existing tator application needs. Will inquire with devs.
  #may need exemption

  #CIS 2.2: Ensure network traffic is restricted between containers on the default bridge
  #another one I should check with tator team to make sure it is intended behavior.

  #CIS 2.3: Ensure the logging level is set to 'info' (Manual)

  # 2.2/2.3/2.8/2.14/2.15/2.16/3.17/5.3
  provisioner "file" {
    source      = "./docker_server_scripts/daemon.json"
    destination = "daemon.json"
  }

  provisioner "shell" {
    inline        = ["sudo mv daemon.json /etc/docker/daemon.json"]
    remote_folder = "."
  }

  #reqs reboot, but should be good to go by provision time.

  #2.4 Ensure Docker is allowed to make changes to iptables (Manual)
  #parameter defaults to true, no changes made

  #2.5 Ensure insecure registries are not used (Manual)
  #not applicable for initial configuration

  #2.6 Ensure aufs storage driver is not used
  #not applicable for initial configuration

  #2.7 Ensure TLS authentication for Docker daemon is configured
  #no plans to make docker daemon remotely available over a TCP port, so not configuring tls for dockerd for now

  #2.8 Ensure the default ulimit is configured appropriately
  #see contents of daemon.json in docker_server_scripts
  #set to default values- not that I have any idea what it means. Sounds like you can override this in the container anyways.

  #2.9 Enable user namespace support
  #recommend exemption
  #The language here mentions that this breaks some docker features. It is useful if the use-case supports it, but if the use case
  #is general or compatibility is unknown it makes more sense to proceed without for initial configuration.

  #2.10 Ensure the default cgroup usage has been confirmed
  #default is left unchanged.

  #2.11 Ensure base device size is not changed until needed
  #default is left unchanged.

  #2.12 Ensure that authorization for Docker client commands is enabled
  #recommend exemption (level 2)
  #rationale: suggested implementation of authorization plugins is work to be done by an adminstrator with an idea of what
  #constitutes acceptible and unacceptable use of specific docker commands. we are not to that point, and this server should be a general
  #resource with full functionality to docker users. Risk in general is diminished- this is a dev environment, GCP limits affected resources
  #via service account permissions, no user sensitive info loaded on the server, etc.

  #2.13 Ensure centralized and remote logging is configured
  #recommend exemption
  #rationale: logs can be manually rotated. A more holistic/automated solution to rotating logs for AFSC linux machines (perhaps it exists)
  #will be explored in the meantime.

  #2.14 Ensure containers are restricted from acquiring new privileges
  #see contents of daemon.json in docker_server_scripts

  #2.15 Ensure live restore is enabled
  #see contents of daemon.json in docker_server_scripts

  #2.16 Ensure Userland Proxy is Disabled
  #see contents of daemon.json in docker_server_scripts

  #2.17 Ensure that a daemon-wide custom seccomp profile is applied if appropriate
  #recommend exemption.
  #like with 2.12, this is done by an adminstrator fully aware of use patterns. We are not there yet,
  #but could be implemented later.

  #2.18 Ensure that experimental features are not implemented in production
  #set as not experimental by default.

  #3.1 - 3.7:
  #refer to keeping default settings as defaults- can assume these are set up
  #correctly on a fresh install. Spot checked a few to confirm.

  #3.8: Ensure that registry certificate file permissions are set to 444 or more restrictively
  #not applicable for fresh install.

  #3.9-3.14: TLS certificate file permissions
  #not applicable, TLS not configured

  #3.15-3.16:
  #nothing to modify on fresh install

  #3.17 Ensure that the daemon.json file ownership is set to root:root
  #confirmed daemon.json is owned by root:root

  #3.18 Ensure that daemon.json file permissions are set to 644 or more restrictive
  #packer load process gives the file 640 permissions, confirmed more restrictive that recommended 644

  #3.19: Ensure that the /etc/default/docker file ownership is set to root:root
  #3.20: Ensure that the /etc/default/docker file ownership is set to root:root
  #confirmed

  #3.21-3.22: Ensure that the /etc/sysconfig/docker file permissions/ownership
  #file doesn't exist on fresh install, not applicable.

  #3.23-3.24 Containerd socket file
  ##nothing to modify on fresh install

  #4.x: a lot of more use guidance type controls
  #4.1-4.4
  #no config

  #4.5: Ensure Content trust for Docker is Enabled
  #set this as global variable for all users
  provisioner "shell" {
    inline        = ["echo DOCKER_CONTENT_TRUST=1 | sudo tee -a /etc/environment"]
    remote_folder = "."
  }

  #4.6-4.7
  #no config

  #4.8: Ensure setuid and setgid permissions are removed
  #not applicable for initial config.

  #4.9-4.12:
  #no config

  #5.1 Ensure swarm mode is not Enabled, if not needed
  #default value false, confirmed.

  #5.2 Ensure that, if applicable, an AppArmor Profile is enabled
  #no running containers to confirm, but default AppArmor profile should be applied to fresh install.

  #5.3 Ensure that, if applicable, SELinux security options are set
  #set in daemon.json.

  #5.4 - 5.29 : run/buildtime of container images (container-side config), and their correct use
  #not initial config.

  #5.30 Ensure that Docker's default bridge "docker0" is not used (Manual)
  #This is a networking detail- it suggests that custom docker networks should be set up and not to rely on the default.
  #however, this is getting into ports/networking. will get into this once I learn more about civision regs.
  #tator seems to create it's own network "public"

  #5.31-5.32: run/buildtime of container images (container-side config), and their correct use
  #not initial config.

  #6.1/6.2: ensure that image sprawl is avoided.
}
