# powershell-vmware-powercli

This repository houses PowerShell scripts for deploying Amazon Linux 2 images to vSphere.

Assumptions:
- The OVA must be downloaded and stored on a local drive or network share, URL is not supported
- You must create a *seed.iso* file includes the meta-data and user-data files
  - meta-data sets the initial hostname and network preference (DHCP)
  - user-data sets the ec2-user password, creates an ansible user and specifies the public SSH key
