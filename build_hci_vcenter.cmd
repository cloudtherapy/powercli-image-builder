@echo off & setlocal

powershell.exe -file deploy-amazon-linux2.ps1^
 -VCenter "hci-vcenter.cetech-ne.local"^
 -ClusterName "NTAP"^
 -DatastoreISO "nfs_vsidata_ds1"^
 -VMNetwork "VM_Network"