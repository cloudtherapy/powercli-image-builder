@echo off & setlocal

powershell.exe -file deploy-amazon-linux2.ps1^
 -VCenter "norw-vcenter.cetech-ne.local"^
 -ClusterName "HP 320"^
 -DatastoreCluster "pure_ds"^
 -DatastoreISO "pure_ds01"^
 -VMNetwork "VM Network"