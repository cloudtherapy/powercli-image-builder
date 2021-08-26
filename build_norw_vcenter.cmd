@echo off & setlocal

powershell.exe -file deploy-amazon-linux2.ps1^
 -VCenter "norw-vcenter.cetech-ne.local"^
 -ClusterName "HP 320"^
 -DatastoreCluster "pure_ds"^
 -VMNetwork "VM Network"