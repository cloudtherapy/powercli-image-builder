# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

param(
    [String]$Environment="hci",
    [String]$VMName="cetech-amzn2",
    [String]$DiskFormat="Thin",
    [String]$Folder="Templates",
    [String]$clibName="cetech-images",
    [String]$clibItemName="cetech-amzn2-seed"
)

if ($Environment -eq "hci") {
    $VCenter="hci-vcenter.cetech-ne.local"
    $ClusterName="NTAP"
    $DatastoreCluster="NetApp-HCI-Datastore"
    $VMNetwork="VM_Network"
} elseif ($Environment -eq "norwood") {
    $VCenter="norw-vcenter.cetech-ne.local"
    $ClusterName="HP 320"
    $DatastoreCluster="pure_ds"
    $VMNetwork="VM Network"
} elseif ($Environment -eq "ntnx") {
    $VCenter="ntnx-vcenter.cetech-ne.local"
    $ClusterName="Lenovo-NTNX"
    $DatastoreCluster="default-container-esx"
    $VMNetwork="VM Network"
} else {
    Write-Output "Please enter a valid environment: hci,norwood,ntnx"
    exit 1
}

# Do not participate in CEIP and ignore SSL warning for vcenter connection
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core

# Connect to VCenter (Prompt for user credentials)
if ($env:vcenter_pass) {
    Write-Output "Connect to VCenter"  
} else {
    Write-Output "Please set environment variable vcenter_pass"
    exit 1
}

Connect-VIServer $VCenter -User administrator@vsphere.local -Password $env:vcenter_pass | Out-Null

# vSphere Cluster + Network configuration parameters
$Cluster = Get-Cluster -Name $ClusterName
# TODO: VM Host is selected by memory. Review for improvement.
$VMHost = Get-Cluster $Cluster | Get-VMHost | Sort-Object MemoryGB | Select -first 1

if ($ClusterName -eq "Lenovo-NTNX") {
    $Datastore = Get-Datastore -Name $DatastoreCluster
} else {
    $Datastore = Get-DatastoreCluster -Name $DatastoreCluster
}
    

# Delete existing template
$template = Get-Template $VMName -ErrorAction SilentlyContinue
if ($template) {
    Write-Output "Existing template found. Removing existing template"
    Remove-Template -Template $VMName -DeletePermanently -Confirm:$false | Out-Null
} else {
    Write-Output "No existing template found"
}

# Fetch OVA from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary $clibName -Name $VMName

# Fetch ISO from Content Library
$iso = Get-ContentLibraryItem -ContentLibrary $clibName -Name $clibItemName

# Build OVF Configuration for OVA
# Write-Output "Build OVF Configuration"
# $userData = Get-Content -Path '.\user-data' -Raw
$ovfConfig = Get-OvfConfiguration -ContentLibraryItem $ova -Target $Cluster
# $ovfConfig.Common.user_data.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
$ovfConfig.NetworkMapping.bridged.Value = $VMNetwork

# Launch VM from OVA
Write-Output "Launch new VM"
New-VM -ContentLibraryItem $ova -OvfConfiguration $ovfConfig -Name $VMName -ResourcePool $VMHost -Location $Folder -Datastore $Datastore -Confirm:$false | Out-Null
$VM = Get-VM $VMName

if ($VM) {
    
    # Add CD-Drive to VM and mount seed.iso
    Write-Output "Mount seed ISO on VM CD/DVD drive"
    New-CDDrive -VM $VM -ContentLibraryIso $iso | Out-Null

    # Boot VM with seed.iso mounted at first boot
    Write-Output "Booting VM"
    Start-VM $VM | Out-Null

    # Wait 2 minutes for updates to occur
    Write-Output "VM Boot and configuration. Wait for 120 seconds..."
    Start-Sleep -Seconds 120

    # Shutdown VM
    Write-Output "Shutdown VM"
    Shutdown-VMGuest $VM -Confirm:$false | Out-Null

    # Wait 15 seconds for power down to occur
    Write-Output "VM Power Down. Wait for 15 seconds..."
    Start-Sleep -Seconds 15

    # Remove seed ISO from VM CD/DVD drive
    Write-Output "Remove seed ISO from VM CD/DVD drive"
    Remove-CDDrive -CD (Get-CDDrive -VM $VM) -Confirm:$false | Out-Null

    # Convert VM to Template
    # TODO: Output to Content Library
    Write-Output "Convert VM to Template"
    Get-VM -Name $VMName | Set-VM -ToTemplate -Confirm:$false | Out-Null

} else {
    Write-Output "VM Failed to launch"
}

# Disconnect from VCenter
Write-Output "Disconnect from VCenter"
Disconnect-VIServer $VCenter -Confirm:$false
