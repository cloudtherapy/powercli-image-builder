# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

Connect-VIServer norw-vcenter.cetech-ne.local

# Load OVF/OVA configuration from NAS share into a variable

$ovfPath = "\\purenas\downloads\OVAs\amzn2-vmware_esx-2.0.20210617.0-x86_64.xfs.gpt.ova"
$ovfConfig = Get-OvfConfiguration -Ovf $ovfPath

# vSphere Cluster + Network configurations
$Cluster = Get-Cluster -Name "HP 320"
$VMName = "cetech-amzn2"
$VMNetwork = "VM Network"
$DatastoreISO = "pure_ds01"

$VMHost = Get-Cluster $Cluster | Get-VMHost | Sort MemoryGB | Select -first 1
$Datastore = Get-Datastore | Sort FreeSpaceGB -Descending | Select -first 1

$DiskFormat = "Thin"
$Folder = "Templates"

# Delete existing template
Remove-Template -Template $VMName -DeletePermanently -Confirm:$false

# Copy seed.iso file from NAS share to datastore
$DatastoreTemp = Get-Datastore $DatastoreISO
New-PSDrive -Location $DatastoreTemp -Name ds -PSProvider VimDatastore -Root "\"
Copy-DatastoreItem -Item "\\purenas\downloads\OVAs\seed.iso" -Destination "ds:\ISO\Amazon\"
Remove-PSDrive -Name ds

# vSphere Network Mapping based on OVF/OVA configuration
$ovfConfig.NetworkMapping.bridged.Value = $VMNetwork

# Deploy the OVF/OVA with the config parameters
Import-VApp -Source $ovfpath -OvfConfiguration $ovfConfig -Name $VMName -VMHost $VMHost -Location $Cluster -Datastore $Datastore -DiskStorageFormat $DiskFormat -InventoryLocation $Folder -Confirm:$false

$VM = Get-VM $VMName

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
$CD = Get-CDDrive -VM $VM
Remove-CDDrive -CD $CD -Confirm:$false

# Convert VM to Template
Get-VM -Name $VMName | Set-VM -ToTemplate -Confirm:$false