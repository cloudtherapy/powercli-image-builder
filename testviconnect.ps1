# Keith Laughman
# www.cloudmethodsllc.com
# Test CodeBuild script to validate network connection and output

param(
    [String]$VCenter="hci-vcenter.cetech-ne.local",
    [String]$ClusterName="NTAP",
    [String]$DatastoreCluster="NetApp-HCI-Datastore",
    [String]$VMNetwork="VM_Network",
    [String]$VMName="cetech-amzn2",
    [String]$DiskFormat="Thin",
    [String]$Folder="Templates",
    [String]$clibName="cetech-images",
    [String]$clibItemName="cetech-amzn2-seed"
)

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core

# Set connection for SSL to Warn
Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Warn -Confirm:$false

# Connect to VCenter (Prompt for user credentials)
Write-Output "Connect to VCenter"
Connect-VIServer $VCenter -User administrator@vsphere.local -Password CETechPass123!

# vSphere Cluster + Network configuration parameters
$Cluster = Get-Cluster -Name $ClusterName
Write-Output "Successful Connection to:" $Cluster
