# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core

# Connect to VCenter (Prompt for user credentials)
Connect-VIServer hci-vcenter.cetech-ne.local

# vSphere Cluster + Network configuration parameters
$Cluster = Get-Cluster -Name "NTAP"
$VMName = "cetech-amzn2"
$VMNetwork = "VM_Network"
$DatastoreISO = "nfs_vsidata_ds1"

$VMHost = Get-Cluster $Cluster | Get-VMHost | Sort MemoryGB | Select -first 1
$Datastore = Get-Datastore | Sort FreeSpaceGB -Descending | Select -first 1

$DiskFormat = "Thin"
$Folder = "Templates"

# Delete existing template
$template = Get-Template $VMName -ErrorAction SilentlyContinue
if ($template) {
    Remove-Template -Template $VMName -DeletePermanently -Confirm:$false
} else {
    Write-Host "No existing template found"
}

# Copy seed.iso file from NAS share to datastore
$DatastoreTemp = Get-Datastore $DatastoreISO
New-PSDrive -Location $DatastoreTemp -Name ds -PSProvider VimDatastore -Root "\"
Copy-DatastoreItem -Item "\\prodnas\downloads\OVAs\seed.iso" -Destination "ds:\ISO\Amazon\"
Remove-PSDrive -Name ds

# Fetch OVA from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2

# Build OVF Configuration for OVA
$userData = Get-Content -Path '.\user-data' -Raw
$ovfConfig = Get-OvfConfiguration -ContentLibraryItem $ova -Target $VMHost
# $ovfConfig.Common.user_data.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
$ovfConfig.NetworkMapping.bridged.Value = $VMNetwork

# Launch VM from OVA
$VM = New-VM -ContentLibraryItem $ova -Name $VMName -VMHost $VMHost -Location $Folder -Datastore $Datastore -DiskStorageFormat $DiskFormat -Confirm:$false

# Add CD-Drive to VM and mount seed.iso
New-CDDrive -VM $VM -IsoPath "[$DatastoreISO] ISO\Amazon\seed.iso" -StartConnected

# Boot VM with seed.iso mounted at first boot
Start-VM $VM

# Wait 2 minutes for updates to occur
Start-Sleep -Seconds 120

# Shutdown VM
Shutdown-VMGuest $VM -Confirm:$false

# Wait 30 seconds for power down to occur
Start-Sleep -Seconds 30

# Assign CD to variable in order to remove it
### $CD = Get-CDDrive -VM $VM
### Remove-CDDrive -CD $CD -Confirm:$false

# Convert VM to Template
Get-VM -Name $VMName | Set-VM -ToTemplate -Confirm:$false

# Disconnect from VCenter
Disconnect-VIServer -Confirm:$false