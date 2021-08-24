@echo off & setlocal

powershell.exe -file deploy-amazon-linux2.ps1^
 -VCenter "ntnx-vcenter.cetech-nj.local"^
 -ClusterName "Lenovo-NTNX"^
 -DatastoreISO "default-container-esx"^
 -VMNetwork "Server Network"