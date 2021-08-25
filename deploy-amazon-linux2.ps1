﻿# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

param(
    [String]$VCenter="hci-vcenter.cetech-ne.local",
    [String]$ClusterName="NTAP",
    [String]$DatastoreISO="nfs_vsidata_ds1",
    [String]$DatastoreCluster="NetApp-HCI-Datastore",
    [String]$VMNetwork="VM_Network",
    [String]$VMName="cetech-amzn2",
    [String]$DiskFormat="Thin",
    [String]$Folder="Templates",
    [String]$clibName="cetech-images",
    [String]$clibItemName="seed"
)

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core

# Connect to VCenter (Prompt for user credentials)
Write-Output "Connect to VCenter"
Connect-VIServer $VCenter

# vSphere Cluster + Network configuration parameters
$Cluster = Get-Cluster -Name $ClusterName
# TODO: VM Host is selected by memory. Review for improvement.
$VMHost = Get-Cluster $Cluster | Get-VMHost | Sort MemoryGB | Select -first 1

$Datastore = Get-DatastoreCluster -Name $DatastoreCluster

# Delete existing template
$template = Get-Template $VMName -ErrorAction SilentlyContinue
if ($template) {
    Write-Output "Existing template found. Removing existing template"
    Remove-Template -Template $VMName -DeletePermanently -Confirm:$false | Out-Null
} else {
    Write-Output "No existing template found"
}

# Fetch OVA from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2

# Fetch ISO from Content Library
$iso = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2-seed

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

    $clib = Get-ContentLibrary -Name $cLibName

    $clibDS = Get-Datastore -Name $clib.Datastore
    New-PSDrive -Name DS -PSProvider VimDatastore -Root '\' -Location $clibDS | Out-Null
    $isoPath = Get-ChildItem -Path "DS:" -Recurse -Filter "$($cLibItemName)*.iso" | Select -ExpandProperty DatastoreFullPath
    Remove-PSDrive -Name DS -Confirm:$false | Out-Null
    
    Write-Output "Mount seed ISO on VM CD/DVD drive"
    New-CDDrive -VM $VM -IsoPath $isoPath -StartConnected | Out-Null

    # Boot VM with seed.iso mounted at first boot
    Write-Output "Booting VM"
    Start-VM $VM | Out-Null

    # Wait 2 minutes for updates to occur
    Write-Output "VM Boot and configuration. Wait for 120 seconds..."
    Start-Sleep -Seconds 120

    # Shutdown VM
    Write-Output "Shutdown VM"
    Shutdown-VMGuest $VM -Confirm:$false | Out-Null

    # Wait 10 seconds for power down to occur
    Write-Output "VM Power Down. Wait for 10 seconds..."
    Start-Sleep -Seconds 10

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