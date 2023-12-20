# Carlos Moreira
# Deployment of Amazon Linux 2 in vCenter/vSphere

<#
    .SYNOPSIS
    Build and customize an Amazon Linux 2 virtual machine in VMWare

    .DESCRIPTION
    Deploy an Amazon Linux 2 virtual machine (VM) from OVA. Customize the image with
    user-data at launch. After customization, shutdown the VM and convert to template.

    .PARAMETER Environment
    Specify target VCenter environment: hci, norw, tp

    .INPUTS
    None.

    .OUTPUTS
    None.

    .EXAMPLE
    Build image in TierPoint cluster:

    PS> build-vmware-amazon2.ps1 -VCenter hci

    .EXAMPLE
    Build image in Norwood cluster:

    PS> build-vmware-amazon2.ps1 -VCenter norw

    .EXAMPLE
    Build image in custom VCenter cluster:

    PS> build-vmware-amazon2.ps1 -VCServer vcenter.local -ClusterName ESX_Cluster -DatastoreName Storage1 -Network Name VM_Network

    .LINK
    https://github.com/cloudtherapy/powercli-image-builder/

#>

param(
    [String] $VCenter="hci",
    [String] $VMName="cetech-amzn2",
    [String] $DiskFormat="Thin",
    [String] $Folder="Templates",
    [String] $SourceContentLibrary="cetech-images",
    [String] $TargetContentLibrary="cetech-images",
    [String] $SourceOva="amzn2",
    [String] $TargetOva="cetech-amzn2",
    [String] $SourceIso="amzn2-seed",
    [String] $VMVersion="vmx-15",
    [Switch] $Release,
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
    $VCServer="hci-vcenter.cetechllc.local"
    $ClusterName="NTAP"
    $DatastoreName="NetApp-HCI-Datastore"
    $NetworkName="VM Network"
} else {
    Write-Output "ERROR: Unknown VCenter. Valid environments: hci,custom"
    exit 1
}

# Ignore SSL warning for VCenter connection
Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Import PowerCLI Modules
Import-Module VMware.VimAutomation.Core -WarningAction SilentlyContinue

# Connect to VCenter 
if ($env:VCENTER_PASSWORD) {
    Write-Output "Connect to VCenter ${VCServer}"
    Connect-VIServer $VCServer -User svc_vcenter@cetechllc.local -Password $env:VCENTER_PASSWORD | Out-Null
} else {
    Write-Output "ERROR: Please set environment variable VCENTER_PASSWORD"
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
if ($ClusterName -eq "HP" -or $VCenter -eq "custom") {
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

# Fetch OVA and Seed ISO from Content Library
$ova = Get-ContentLibraryItem -ContentLibrary $SourceContentLibrary -Name $SourceOva

# Update seed.iso in ContentLibrary when variable set to True
$seed_iso = Get-ContentLibraryItem -ContentLibrary $SourceContentLibrary -Name $SourceIso -ErrorAction SilentlyContinue
if ($seed_iso) {
    if ($UpdateSeedIso -And $VCenter -eq "hci" -or $VCenter -eq "custom") {
        Write-Output "Updating existing seed.iso file in the Content Library"
        $seedfile = Resolve-Path -Path(Get-Item seedconfig-amzn2\seed.iso)
        $seed_iso = Set-ContentLibraryItem -ContentLibraryItem $SourceIso -Files $seedfile.Path 
    }
} else {
    Write-Output "Content Library item not found. Creating the seed ISO"
    $seedfile = Resolve-Path -Path(Get-Item seedconfig-amzn2\seed.iso)
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
Set-VM -VM $VM -HardwareVersion $VMVersion -Confirm:$false | Out-Null

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
            Write-Output "ERROR: VM Failed to Power Down (Stopped and Removed)"
            Stop-VM $VM -Confirm:$false | Out-Null
            Remove-VM -VM $VM -DeletePermanently -Confirm:$False | Out-Null
            exit 1
        }
            
    }

    Write-Output "Waited $time second(s) for VM to Power Down."

    # Remove seed ISO from VM CD/DVD drive
    Write-Output "Remove seed ISO from VM CD/DVD drive"
    Remove-CDDrive -CD (Get-CDDrive -VM $VM) -Confirm:$false | Out-Null

    # Update Note on Template
    # Release type [ daily ] Build date [ 2021-06-11 17:53:35 UTC ]
    $releasedate = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    if ($Release) {
        $NewNote = "Release type [ release ] Build date [ $releasedate ]"
    } else {
        $NewNote = "Release type [ daily ] Build date [ $releasedate ]"
        $TargetOva = "daily-" + $TargetOva
    }

    # Creating Template from VM and storing in Content Library
    Write-Output "Convert VM to Template and store in Content Library"
    $target = Get-ContentLibraryItem -ContentLibrary $TargetContentLibrary -Name $TargetOva -ErrorAction SilentlyContinue
    if ($target) {
        Write-Output "Updating existing VM Template in Content Library"
        Set-ContentLibraryItem -ContentLibraryItem $target -VM $VMName | Out-Null
        Set-ContentLibraryItem -ContentLibraryItem $target -Notes $NewNote | Out-Null
    } else {
        Write-Output "VM template not found. Creating Content Library item"
        New-ContentLibraryItem -ContentLibrary $TargetContentLibrary -VM $VMName -Name $TargetOva -Notes $NewNote | Out-Null
    }

    Write-Output "Deleting VM"
    Remove-VM -VM $VM -DeletePermanently -Confirm:$False | Out-Null

    # Troubleshooting section - creates a VM Template
    # Write-Output "Convert VM to Template"
    # Get-VM -Name $VMName | Set-VM -ToTemplate -Confirm:$false | Out-Null
} else {
    Write-Output "ERROR: VM Failed to launch"
}

# Disconnect from VCenter
Write-Output "Disconnect from VCenter"
Disconnect-VIServer $VCServer -Confirm:$false
