# powercli-image-builder

This repository houses a PowerShell script for deploying Amazon Linux 2 images to VMware environments.

Requirements:
- The initlal OVA and ISO are stored in a local Content Library (VMware)
- The inital OVA can be downloaded from here:
  - https://cdn.amazonlinux.com/os-images/2.0.20220805.0/vmware/amzn2-vmware_esx-2.0.20220805.0-x86_64.xfs.gpt.ova
- Upload the OVA to Content Library and set name to amazon2
- #TODO: Figure out how to deploy in Hyper-V
- You must create a *seed.iso* file which includes the meta-data and user-data files
  - meta-data sets the initial hostname and network preference (DHCP)
  - user-data creates an ansible user and associates its public SSH key
