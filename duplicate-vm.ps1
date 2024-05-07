# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

function DuplicateDisk {

    param (
        $sourceDiskName,
        $trustedLaunch = $false
    )

    # Get the source disk
    Write-Host "---> Getting the VM old disk informations"
    $sourceDisk = Get-AzDisk -ResourceGroupName $rgName -DiskName $sourceDiskName
    
    # Generate a name for the new disk
    $targetDiskName = "${sourceDiskName}_noade"

    # Check if the new disk already exists
    try {
        $targetDisk = Get-AzDisk -ResourceGroupName $rgName -DiskName $targetDiskName
        Write-Host "---> Duplicate disk already exists"
    }
    # If not, create a new one
    catch {
        # Check if it's a OS or DATA disk
        $hyperVGeneration = $sourceDisk.HyperVGeneration
        
        # Adding the sizeInBytes with the 512 offset, and the -Upload flag
        Write-Host "---> Creating the new disk config"
        $targetDiskconfig = New-AzDiskConfig -SkuName $($sourceDisk.Sku.Name) -osType $($sourceDisk.OsType) -UploadSizeInBytes $($sourceDisk.DiskSizeBytes+512) -Location $($sourceDisk.Location) -CreateOption 'Upload' -HyperVGeneration $($sourceDisk.HyperVGeneration)

        # If we need trusted launch for the VM
        $targetDiskconfig = Set-AzDiskSecurityProfile -Disk $targetDiskconfig -SecurityType "TrustedLaunch";
        
        # Create the new disk
        Write-Host "---> Creating the disk in Azure"
        $targetDisk = New-AzDisk -ResourceGroupName $rgName -DiskName $targetDiskName -Disk $targetDiskconfig
        
        # Get the source and destination disk SAS
        Write-Host "---> Getting a read SAS token for the old disk"
        $sourceDiskSas = Grant-AzDiskAccess -ResourceGroupName $rgName -DiskName $sourceDiskName -DurationInSecond 86400 -Access 'Read'
        Write-Host "---> Getting a write SAS token for the new disk"
        $targetDiskSas = Grant-AzDiskAccess -ResourceGroupName $rgName -DiskName $targetDiskName -DurationInSecond 86400 -Access 'Write'
        
        # Copy the data between the source and destination disk
        Write-Host "---> Running azcopy to transfer the data (this may take a while)"
        azcopy copy $sourceDiskSas.AccessSAS $targetDiskSas.AccessSAS --blob-type PageBlob | Out-Null
        
        # Revoke the SAS
        Write-Host "---> Removing the SAS token for the old disk"
        Revoke-AzDiskAccess -ResourceGroupName $rgName -DiskName $sourceDiskName | Out-Null
        Write-Host "---> Removing the SAS token for the new disk"
        Revoke-AzDiskAccess -ResourceGroupName $rgName -DiskName $targetDiskName | Out-Null
    }

    return $targetDisk

}

# Get the VM
Write-Host "Finding the VM"
$vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName

Write-Host "-> OS Disk"
# Duplicate the OS disk
Write-Host "--> Duplicating the OS disk $($vm.StorageProfile.OsDisk.Name)"
$newDisk = DuplicateDisk $($vm.StorageProfile.OsDisk.Name) $($vm.SecurityProfile.UefiSettings.VTpmEnabled)

# Set the VM configuration to point to the new disk  
Write-Host "--> Swapping the VM OS disk"
Set-AzVMOSDisk -VM $vm -ManagedDiskId $($newDisk.Id) -Name $($newDisk.Name) -CreateOption Attach | Out-Null

Write-Host "-> Data Disks"
# Need to create a duplicate object because we're looping on the object and altering it at the same time
[Array]$vmDataDisk = $()
$vm.StorageProfile.DataDisks | foreach { 
    $vmDataDisk += @{Name=$_.Name; Lun=$($_.Lun)}
}

# Duplicate all the data disks
$vmDataDisk | foreach { 
    # If we have data disk
    if ($_) {
        # Create a new data disk
        Write-Host "--> Duplicating the data disk $($_.Name)"
        $newDisk = DuplicateDisk $($_.Name)

        # Remove the old data disk from the VM
        Write-Host "--> Removing the old data disk $($_.Name)"
        Remove-AzVMDataDisk -VM $vm -Name $($_.Name) | Out-Null

        # Attach the new data disk to the vm with the same LUN
        Write-Host "--> Attaching the new data disk $($newDisk.Name)"
        Add-AzVMDataDisk -VM $vm -Name $($newDisk.Name) -CreateOption Attach -ManagedDiskId $($newDisk.Id) -Lun $($_.Lun) | Out-Null
    }
}

Write-Host "-> Creating the new VM"
# Get the vnet and subnet name
$nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
$nicObj = Get-AzNetworkInterface -ResourceId $nicId
$subnetName = $nicObj.IpConfigurations.Subnet.Id
$vnetName = ($subnetName -split '/')[8]

# Remove some parameters not needed for the creation
$newVm = $vm | Select-Object -Property * -ExcludeProperty Id, VmId, ProvisioningState, RequestId, StatusCode, ResourceGroupName, TimeCreated, OsProfile, NetworkProfile
$newVm.StorageProfile = $vm.StorageProfile | Select-Object -Property * -ExcludeProperty ImageReference
$newVm.Name = "$($vm.Name)_noade"

New-AzVM -VM $newVm -ResourceGroupName $rgName -Location $(vm.Location) -VirtualNetworkName $vnetName -SubnetName $subnetName

