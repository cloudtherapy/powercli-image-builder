# Carlos Moreira
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
    [String]$Folder="Templates"
)

function Set-CDDriveCLIso {
<#
    .SYNOPSIS
    Mount an ISO from a Content Library
    .DESCRIPTION
    This function will mount an ISO located on a Content Library
    on a CDDrive of a VM
    .NOTES
    Author:  Luc Dekens
    Version:
    1.0 24/12/20  Initial release
    .PARAMETER VM
    Specifies the virtual machines on whose guest operating systems
    you want to run the script.
    .PARAMETER CDDrive
    Specifies the CDDrive on which the ISO will be mounted
    .PARAMETER ContentLibrary
    Specifies the Content Library on which the ISO is located.
    .PARAMETER ContentLibraryIso
    Specifies the ISO item on the Content Library
    .EXAMPLE
    $cl = Get-ContentLibrary -Name MyCL
    $iso = Get-ContentLibraryItem -ContentLibrary $cl -Name MyISO
    Get-VM -Name 'MyVM' | Get-CDDrive -Name 'CD/DVD drive 0' |
    Set-CDDriveCLIso -ContentLibraryIso $iso -Confirm:$false
    .EXAMPLE
    $cd = Get-VM -Name MyVM | Get-CDDrive
    Set-CDDriveCLIso -CDDrive $cd -ContentLibraryIso $iso -Confirm:$false
#>
    [cmdletbinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.CDDrive]$CDDrive,
        [parameter(Mandatory = $true)]
        [VMware.VimAutomation.ViCore.Types.V1.ContentLibrary.ContentLibraryItem]$ContentLibraryISO
    )

    $target = "VM:$($CDDrive.Parent.Name) CD:$($CDDrive.Name)"
    $action = "Mount ISO $($ContentLibraryISO.Name) from $($ContentLibraryISO.ContentLibrary.Name)"

    if ($PSCmdlet.ShouldProcess($target, $action)) {
        $driveName = -join ((65..90) | 
            Get-Random -Count 3 | 
            ForEach-Object -Process { [char]$_ })
        $filter = "$($ContentLibraryISO.Name)*.iso" 
        
        $ds = Get-Datastore -Name $ContentLibraryISO.ContentLibrary.Datastore

        New-PSDrive -Name $driveName -PSProvider VimDatastore -Root '\' -Location $ds | Out-Null
        $clPath = Get-ChildItem -Path "$($driveName):" -Filter "$($ContentLibraryIso.Id)" -Recurse |
            Select-Object -ExpandProperty FolderPath
        $isoPath = Get-ChildItem -Path "$($driveName):\$($clPath.Split(' ')[1])" -Filter $filter -Recurse | 
            Select-Object -ExpandProperty DatastoreFullPath
        Remove-PSDrive -Name $driveName -Confirm:$false | Out-Null
        
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        
        $change = New-Object VMware.Vim.VirtualDeviceConfigSpec
        $change.Operation = [Vmware.vim.VirtualDeviceConfigSpecOperation]::edit
        
        $dev = $cd.ExtensionData
        $dev.Backing = New-Object VMware.Vim.VirtualCdromIsoBackingInfo
        $dev.Backing.FileName = $isoPath
        
        $change.Device += $dev
        $change.Device.Connectable.Connected = $true
        
        $spec.DeviceChange = $change
        
        $vm.ExtensionData.ReconfigVM($spec)
        
        Get-CDDrive -Id $CDDrive.Id
    }
}

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

# Copy seed.iso file from NAS share to datastore
# TODO: Replace logic for seed ISO with user data
#Write-Output "Copy seed ISO to local datastore"
#$DatastoreTemp = Get-Datastore $DatastoreISO
#New-PSDrive -Location $DatastoreTemp -Name ds -PSProvider VimDatastore -Root "\" | Out-Null
#Copy-DatastoreItem -Item "\\prodnas\downloads\OVAs\seed.iso" -Destination "ds:\ISO\Amazon\" | Out-Null
#Remove-PSDrive -Name ds | Out-Null

# Fetch OVA from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2

# Fetch ISO from Content Library
$iso = Get-ContentLibraryItem -ContentLibrary cetech-images -Name cetech-amzn2-seed

# Build OVF Configuration for OVA
Write-Output "Build OVF Configuration"
$userData = Get-Content -Path '.\user-data' -Raw
$ovfConfig = Get-OvfConfiguration -ContentLibraryItem $ova -Target $VMHost
# $ovfConfig.Common.user_data.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
$ovfConfig.NetworkMapping.bridged.Value = $VMNetwork

# Launch VM from OVA
Write-Output "Launch new VM"
New-VM -ContentLibraryItem $ova -Name $VMName -ResourcePool $Cluster -Location $Folder -Datastore $Datastore -DiskStorageFormat $DiskFormat -Confirm:$false | Out-Null
$VM = Get-VM $VMName

if ($VM) {

    # Add CD-Drive to VM and mount seed.iso
    Write-Output "Mount seed ISO on VM CD/DVD drive"
    #$cd = New-CDDrive -VM $VM -StartConnected
    $cl = Get-ContentLibrary -Name cetech-images
    $iso = Get-ContentLibraryItem -ContentLibrary $cl -Name cetech-amzn2-seed
    Get-VM -Name $VMName | Get-CDDrive -Name 'CD/DVD drive 0' |
    Set-CDDriveCLIso -ContentLibraryIso $iso -Confirm:$false
    #$cd = Get-VM -Name $VMName | Get-CDDrive
    #Set-CDDriveCLIso -CDDrive $cd -ContentLibraryIso $iso -Confirm:$false
    #Get-CDDrive -VM $VM -Name "CD/DVD drive 1" | Out-Null
    #Set-CDDriveCLIso -VM $VM -ContentLibraryIso $clISO -Confirm:$false | Out-Null
    #Get-VM $VM | New-CDDrive -VM $VM -ContentLibraryIso $clISO -StartConnected | Out-Null
    #New-CDDrive -VM $VM -IsoPath "[$DatastoreISO] ISO\Amazon\seed.iso" -StartConnected | Out-Null

    # Boot VM with seed.iso mounted at first boot
    Write-Output "Booting VM"
    Start-VM $VM | Out-Null

    # Wait 2 minutes for updates to occur
    Write-Output "VM Boot and configuration. Wait for 90 seconds..."
    Start-Sleep -Seconds 90

    # Shutdown VM
    Write-Output "Shutdown VM"
    Shutdown-VMGuest $VM -Confirm:$false | Out-Null

    # Wait 30 seconds for power down to occur
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
#Disconnect-VIServer $VCenter -Confirm:$false