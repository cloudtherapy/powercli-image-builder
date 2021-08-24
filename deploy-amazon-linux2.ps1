# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

param(
    [String]$VCenter="hci-vcenter.cetech-ne.local",
    [String]$ClusterName="NTAP",
    [String]$DatastoreISO="nfs_vsidata_ds1",
    [String]$VMNetwork="VM_Network",
    [String]$VMName="cetech-amzn2",
    [String]$DiskFormat="Thin",
    [String]$Folder="Templates"
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
# TODO: Datastore is selected by capacity. Review for improvement.
$Datastore = Get-Datastore | Sort FreeSpaceGB -Descending | Select -first 1

# Delete existing template
$template = Get-Template $VMName -ErrorAction SilentlyContinue
if ($template) {
    Write-Output "Existing template found. Removing existing template"
    Remove-Template -Template $VMName -DeletePermanently -Confirm:$false | Out-Null
} else {
    Write-Output "No existing template found"
}

# Copy seed.iso file from NAS share to datastore
# TODO: Replace logic for seed ISO with user data
Write-Output "Copy seed ISO to local datastore"
$DatastoreTemp = Get-Datastore $DatastoreISO
New-PSDrive -Location $DatastoreTemp -Name ds -PSProvider VimDatastore -Root "\" | Out-Null
Copy-DatastoreItem -Item "\\prodnas\downloads\OVAs\seed.iso" -Destination "ds:\ISO\Amazon\" | Out-Null
Remove-PSDrive -Name ds | Out-Null

# Fetch OVA from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2

# Build OVF Configuration for OVA
Write-Output "Build OVF Configuration"
$userData = Get-Content -Path '.\user-data' -Raw
$ovfConfig = Get-OvfConfiguration -ContentLibraryItem $ova -Target $VMHost
# $ovfConfig.Common.user_data.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
$ovfConfig.NetworkMapping.bridged.Value = $VMNetwork

# Launch VM from OVA
Write-Output "Launch new VM"
New-VM -ContentLibraryItem $ova -Name $VMName -VMHost $VMHost -Location $Folder -Datastore $Datastore -DiskStorageFormat $DiskFormat -Confirm:$false | Out-Null
$VM = Get-VM $VMName

if ($VM) {

    # Add CD-Drive to VM and mount seed.iso
    Write-Output "Mount seed ISO on VM CD/DVD drive"
    New-CDDrive -VM $VM -IsoPath "[$DatastoreISO] ISO\Amazon\seed.iso" -StartConnected | Out-Null

    # Boot VM with seed.iso mounted at first boot
    Write-Output "Booting VM"
    Start-VM $VM | Out-Null

    # Wait 2 minutes for updates to occur
    Write-Output "VM Boot and configuration. Wait for 120 seconds..."
    Start-Sleep -Seconds 120

    # Shutdown VM
    Write-Output "Shutdown VM"
    Shutdown-VMGuest $VM -Confirm:$false | Out-Null

    # Wait 30 seconds for power down to occur
    Write-Output "VM Power Down. Wait for 30 seconds..."
    Start-Sleep -Seconds 30

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