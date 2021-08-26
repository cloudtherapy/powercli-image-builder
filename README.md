# powercli-image-builder

This repository houses PowerShell scripts for deploying Amazon Linux 2 images to VMware vSphere and Microsoft Hyper-V.

Requirements:
- The OVA and ISO are stored in a local Content Library (VMware)
- #TODO: Figure out how to deploy in Hyper-V
- You must create a *seed.iso* file which includes the meta-data and user-data files
  - meta-data sets the initial hostname and network preference (DHCP)
  - user-data sets the ec2-user password, creates an ansible user and associates its public SSH key
