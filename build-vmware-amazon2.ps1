﻿# Carlos Moreira
# www.cloudmethodsllc.com
# Deployment of Amazon Linux 2 in vCenter/vSphere

<#
    .SYNOPSIS
    Build and customize an Amazon Linux 2 virtual machine in VMWare

    .DESCRIPTION
    Deploy an Amazon Linux 2 virtual machine (VM) from OVA. Customize the image with
    user-data at launch. After customization, shutdown the VM and convert to template.

    .PARAMETER Environment
    Specify target VCenter environment: hci, norwood, ntnx

    .INPUTS
    None.

    .OUTPUTS
    None.

    .EXAMPLE
    Build image in TierPoint cluster:

    PS> build-vmware-amazon2.ps1 -VCenter hci

    .EXAMPLE
    Build image in Norwood cluster:

    PS> build-vmware-amazon2.ps1 -VCenter norwood

    .EXAMPLE
    Build image in Nutanix cluster:

    PS> build-vmware-amazon2.ps1 -VCenter ntnx

    .EXAMPLE
    Build image in custom VCenter cluster:

    PS> build-vmware-amazon2.ps1 -VCServer vcenter.local -ClusterName ESX_Cluster -DatastoreName Storage1 -Network Name VM_Network

    .LINK
    https://github.com/cloudmethods/powercli-image-builder/

#>

param(
    [String] $VCenter="hci",
    [String] $VMName="methods-amzn2",
    [String] $DiskFormat="Thin",
    [String] $Folder="Templates",
    [String] $SourceContentLibrary="methods-images",
    [String] $TargetContentLibrary="methods-images",
    [String] $SourceOva = "amazon2",
    [String] $TargetOva = "methods-amazon2",
    [String] $SourceIso="amazon2-seed",
    [Switch] $UpdateSeedIso,
    [String] $VCServer,
    [String] $ClusterName,
    [String] $DatastoreName,
    [String] $NetworkName
)

# Validate custom input
if ($VCServer -And $ClusterName -And $DatastoreName -And $NetworkName) {
    $VCenter = "custom"
}

# Convert VCenter parameter to lowercase to disable case sensitivity
$Environment = $VCenter.ToLower()
if ($Environment -eq "custom") {
    Write-Output("Custom VCenter: ${VCServer}")
} elseif ($Environment -eq "hci") {
    Write-Output("HCI VCenter (TierPoint)")
    $VCServer="hci-vcenter.cetech-ne.local"
    $ClusterName="NTAP"
    $DatastoreName="NetApp-HCI-Datastore"
    $NetworkName="VM_Network"
} elseif ($Environment -eq "norwood") {
    Write-Output("Norwood VCenter (Norwood, MA)")
    $VCServer="norw-vcenter.cetech-ne.local"
    $ClusterName="HP 320"
    $DatastoreName="pure_ds"
    $NetworkName="VM Network"
} elseif ($Environment -eq "ntnx") {
    Write-Output("Nutanix VCenter (Flemington, NJ)")
    $VCServer="ntnx-vcenter.cetech-ne.local"
    $ClusterName="Lenovo-NTNX"
    $DatastoreName="default-container-esx"
    $NetworkName="VM Network"
} else {
    Write-Output "ERROR: Unknown VCenter. Valid environments: hci,norwood,ntnx"
    exit 1
}

# Ignore SSL warning for VCenter connection
Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core -WarningAction SilentlyContinue

# Connect to VCenter 
if ($env:VCENTER_PASSWORD) {
    Write-Output "Connect to VCenter ${VCServer}"
    Connect-VIServer $VCServer -User administrator@vsphere.local -Password $env:VCENTER_PASSWORD | Out-Null
} else {
    Write-Output "ERROR: Please set environment variable vcenter_pass"
    exit 1
}

# Verify VCenter Connection
if ($global:defaultviserver.Name -eq $VCServer) {
    Write-Output "VCenter Connection Successful"
} else {
    Write-Output "ERROR: VCenter Connection Failed. Please validate connectivity and credentials"
    exit 1
}

# Configure target environment
## ESX Cluster
$Cluster = Get-Cluster -Name $ClusterName
## ESX Server
$VMHost = Get-Cluster $Cluster | Get-VMHost | Sort-Object MemoryGB | Select-Object -first 1
## Datastore
if ($ClusterName -eq "Lenovo-NTNX") {
    $Datastore = Get-Datastore -Name $DatastoreName
} else {
    $Datastore = Get-DatastoreCluster -Name $DatastoreName
}

# Cleanup existing template, if found
$template = Get-Template $VMName -ErrorAction SilentlyContinue
if ($template) {
    Write-Output "Existing template found. Removing existing template"
    Remove-Template -Template $VMName -DeletePermanently -Confirm:$false | Out-Null
}

# Fetch OVA and Seed ISO rom Content Library
$ova = Get-ContentLibraryItem -ContentLibrary $SourceContentLibrary -Name $SourceOva

# Update seed.iso in ContentLibrary when variable set to True
$seed_iso = Get-ContentLibraryItem -ContentLibrary $SourceContentLibrary -Name $SourceIso -ErrorAction SilentlyContinue
if ($seed_iso) {
    if ($UpdateSeedIso -And $VCenter -eq "hci") {
        Write-Output "Updating existing seed.iso file in the Content Library"
        $seedfile = Resolve-Path -Path(Get-Item seedconfig\seed.iso)
        $seed_iso = Set-ContentLibraryItem -ContentLibraryItem $SourceIso -Files $seedfile.Path 
    }
} else {
    Write-Output "Content Library item not found. Creating the seed ISO"
    $seedfile = Resolve-Path -Path(Get-Item seedconfig\seed.iso)
    $seed_iso = New-ContentLibraryItem -ContentLibrary $SourceContentLibrary -Files $seedfile.Path -Name $SourceIso 
}

# Build OVF Configuration for OVA
# Write-Output "Build OVF Configuration"
# $userData = Get-Content -Path '.\user-data' -Raw
$ovfConfig = Get-OvfConfiguration -ContentLibraryItem $ova -Target $Cluster
# $ovfConfig.Common.user_data.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
$ovfConfig.NetworkMapping.bridged.Value = $NetworkName

# Launch VM from OVA
Write-Output "Launch new VM"
New-VM -ContentLibraryItem $ova -OvfConfiguration $ovfConfig -Name $VMName -ResourcePool $VMHost -Location $Folder -Datastore $Datastore -Confirm:$false | Out-Null
$VM = Get-VM $VMName

# Continue if VM launched successfully
if ($VM) {
    
    # Add CD-Drive to VM and mount seed.iso
    Write-Output "Mount seed ISO on VM CD/DVD drive"
    New-CDDrive -VM $VM -ContentLibraryIso $seed_iso | Out-Null

    # Boot VM with seed.iso mounted at first boot
    Write-Output "Booting VM"
    Start-VM $VM | Out-Null

    $vm_state = (Get-VM -Name $VMName).PowerState
    $time = 0

    while ($vm_state -ne "PoweredOff") {
        Start-Sleep -Seconds 1
        $time = $time + 1
        if ($time % 10 -eq 0) {
            Write-Output "Waiting $time seconds for VM to Power Down"
        }
        $vm_state = (Get-VM -Name $VMName).PowerState
        if ($time -eq 300) {
            Write-Output "ERROR: VM Failed to Power Down (Stoped and Removed)"
            Stop-VM $VM -Confirm:$false | Out-Null
            Remove-VM -VM $VM -Confirm:$False | Out-Null
            exit 1
        }
            
    }

    Write-Output "Waited $time second(s) for VM to Power Down."

    # Remove seed ISO from VM CD/DVD drive
    Write-Output "Remove seed ISO from VM CD/DVD drive"
    Remove-CDDrive -CD (Get-CDDrive -VM $VM) -Confirm:$false | Out-Null

    # Creating Template from VM and storing in Content Library
    Write-Output "Convert VM to Template and store in Content Library"
    $target = Get-ContentLibraryItem -ContentLibrary $TargetContentLibrary -Name $TargetOva
    if ($target) {
        Write-Output "Updating existing VM Temaplte in Content Library"
        Set-ContentLibraryItem -ContentLibraryItem $target -VM $VMName 
    } else {
        Write-Output "VM template not found. Creating Content Library item"
        New-ContentLibraryItem -ContentLibrary $TargetContentLibrary -VM $VMName -Name $TargetOva
    }
    Write-Output "Deleting VM"
    Remove-VM -VM $VM -Confirm:$False | Out-Null
} else {
    Write-Output "ERROR: VM Failed to launch"
}

# Disconnect from VCenter
Write-Output "Disconnect from VCenter"
Disconnect-VIServer $VCServer -Confirm:$false
