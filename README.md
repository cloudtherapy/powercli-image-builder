# powercli-image-builder

This repository houses a PowerShell script for deploying Amazon Linux 2 and 2023 images to VMware environments.

Requirements:
- The initlal OVA and ISO are stored in a local Content Library (VMware)
- The inital OVA can be downloaded from here:
  - https://cdn.amazonlinux.com/os-images/latest/
  - https://cdn.amazonlinux.com/al2023/os-images/latest/
- Upload the OVA to Content Library and set name to amzn2/al2023
- You must create a *seed.iso* file which includes the meta-data and user-data files
  - meta-data sets the initial hostname and/or network preference (DHCP)
  - user-data creates both ansible and ec2-user users and associates the public SSH key
