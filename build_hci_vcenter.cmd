@echo off & setlocal

powershell.exe -file deploy-amazon-linux2.ps1^
 -VCenter "hci-vcenter.cetech-ne.local"^
 -ClusterName "NTAP"^
 -DatastoreCluster="NetApp-HCI-Datastore"^
 -VMNetwork "VM_Network"