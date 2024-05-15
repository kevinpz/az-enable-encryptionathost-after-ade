param (
  [switch] $LoadFromFile
)

# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Function used to create a new disk and copy the data from the old one using azcopy
function DuplicateDisk {

    param (
        $sourceDiskName,
        $trustedLaunch = $false
    )

    # Get the source disk
    Write-Host "----> Getting the VM old disk informations"
    $sourceDisk = Get-AzDisk -ResourceGroupName $rgName -DiskName $sourceDiskName
    
    # Generate a name for the new disk
    $targetDiskName = "${sourceDiskName}_noade"

    # Check if the new disk already exists
    try {
        $targetDisk = Get-AzDisk -ResourceGroupName $rgName -DiskName $targetDiskName
        Write-Host "----> Duplicate disk already exists"
    }
    # If not, create a new one
    catch {
        # Check if it's a OS or DATA disk
        $hyperVGeneration = $sourceDisk.HyperVGeneration
        
        # Adding the sizeInBytes with the 512 offset, and the -Upload flag
        Write-Host "----> Creating the new disk config"
        $targetDiskconfig = New-AzDiskConfig -SkuName $($sourceDisk.Sku.Name) -osType $($sourceDisk.OsType) -UploadSizeInBytes $($sourceDisk.DiskSizeBytes+512) -Location $($sourceDisk.Location) -CreateOption 'Upload' -HyperVGeneration $($sourceDisk.HyperVGeneration)

        # If we need trusted launch for the VM
        if($trustedLaunch) {
            $targetDiskconfig = Set-AzDiskSecurityProfile -Disk $targetDiskconfig -SecurityType "TrustedLaunch";
        }
        
        # Create the new disk
        Write-Host "----> Creating the disk in Azure"
        $targetDisk = New-AzDisk -ResourceGroupName $rgName -DiskName $targetDiskName -Disk $targetDiskconfig
        
        # Get the source and destination disk SAS
        Write-Host "----> Getting a read SAS token for the old disk"
        $sourceDiskSas = Grant-AzDiskAccess -ResourceGroupName $rgName -DiskName $sourceDiskName -DurationInSecond 86400 -Access 'Read'
        Write-Host "----> Getting a write SAS token for the new disk"
        $targetDiskSas = Grant-AzDiskAccess -ResourceGroupName $rgName -DiskName $targetDiskName -DurationInSecond 86400 -Access 'Write'
        
        # Copy the data between the source and destination disk
        Write-Host "----> Running azcopy to transfer the data (this may take a while)"
        azcopy copy $sourceDiskSas.AccessSAS $targetDiskSas.AccessSAS --blob-type PageBlob | Out-Null
        
        # Revoke the SAS
        Write-Host "----> Removing the SAS token for the old disk"
        Revoke-AzDiskAccess -ResourceGroupName $rgName -DiskName $sourceDiskName | Out-Null
        Write-Host "----> Removing the SAS token for the new disk"
        Revoke-AzDiskAccess -ResourceGroupName $rgName -DiskName $targetDiskName | Out-Null
    }

    return $targetDisk

}

# In case something went wrong in the previous execution and the source VM is deleted, load the sourceVM config from file
try {
    # Get the VM
    Write-Host "-> Finding the source VM"
    $vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName
    Write-Host "--> Source VM found in Azure"

    # Checking powerstate
    Write-Host "-> Checking VM power state"
    $vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
    $powerState = $vm.Statuses[1].Code

    if ($powerState -eq "PowerState/running") {
        Write-Host "--> VM is running. VM should be stopped to copy the disks. Stopping the VM $vmName..."
        Stop-AzVM -ResourceGroupName $rgName -Name $vmName -Confirm

        # Checking if the VM is stopped now
        $vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
        $powerState = $vm.Statuses[1].Code
        if ($powerState -eq "PowerState/running") {
            throw "VM is still running"
        }
    }

    # Update deleteoption properties
    Write-Host "-> Updating the delete behavior on the source VM $vmName (keep everything)"
    $vmSource.StorageProfile.OsDisk.DeleteOption = 'Detach'
    $vmSource.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Detach' }
    $vmSource.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Detach' }
    $vmSource | Update-AzVM | Out-Null

    # Saving the original VM object to the disk, just in case ...
    Write-Host "-> Saving the VM config to file just in case :)"
    $vmSource | Export-Clixml sourceVm.xml -Depth 20
}
catch {
    Write-Host "--> Can't find the source VM in Azure anymore, loading source VM config from file"
    $vmSource=Import-Clixml -Path sourceVm.xml
    $vmSourceDeleted = $true
}

# Creating the new VM config object
Write-Host "-> Creating the new VM config"
$vmDestination = New-AzVMConfig -VMName $vmName -VMSize $($vmSource.HardwareProfile.VmSize) -Tags $($vmSource.Tags)
$vmDestination.SecurityProfile = $vmSource.SecurityProfile
if($vmSource.LicenseType) {
    $vmDestination.LicenseType = $vmSource.LicenseType
}

# Attaching the source NIC(s) to the new VM
Write-Host "-> Attaching the NIC(s) to the new VM"
$vmSource.NetworkProfile.NetworkInterfaces | foreach { 
    $nicName = $($_.Id).Split("/")[-1]
    Write-Host "--> Attaching the NIC: $nicName"
    # If this is the primary network card
    if ($_.Primary)
    {
        Add-AzVMNetworkInterface -VM $vmDestination -Id $_.Id | Out-Null
        #TBD Add-AzVMNetworkInterface -VM $vmDestination -Primary -Id $_.Id | Out-Null
    }
    else {
        Add-AzVMNetworkInterface -VM $vmDestination -Id $_.Id | Out-Null
    }
}

# Create new disks and duplicate the data from the old one
Write-Host "-> Duplicating the disks"

# OS disk
## Duplicate the OS disk
Write-Host "--> OS Disk"
Write-Host "---> Duplicating the OS disk $($vmSource.StorageProfile.OsDisk.Name)"
$newOsDisk = DuplicateDisk $($vmSource.StorageProfile.OsDisk.Name) $($vmSource.SecurityProfile.UefiSettings.VTpmEnabled)

## Set the VM configuration to point to the new disk  
Write-Host "---> Setting the VM OS disk"
Set-AzVMOSDisk -VM $vmDestination -ManagedDiskId $($newOsDisk.Id) -Name $($newOsDisk.Name) -CreateOption Attach | Out-Null
$vmDestination.StorageProfile.osDisk.osType = $vmSource.StorageProfile.osDisk.osType

# OS disk(s)
Write-Host "--> Data Disks"

## Duplicate all the data disks
$vmSource.StorageProfile.DataDisks | foreach { 
    # If we have data disk
    if ($_) {
        # Create a new data disk
        Write-Host "---> Duplicating the data disk $($_.Name)"
        $newDisk = DuplicateDisk $($_.Name)

        # Attach the new data disk to the vm with the same LUN
        Write-Host "---> Attaching the new data disk $($newDisk.Name)"
        Add-AzVMDataDisk -VM $vmDestination -Name $($newDisk.Name) -CreateOption Attach -ManagedDiskId $($newDisk.Id) -Lun $($_.Lun) | Out-Null
    }
}

# Delete the source VM
if(-Not($vmSourceDeleted)) {
    Write-Host "-> Removing the source VM $($vmSource.Id)"
    Remove-AzVm -Id $($vmSource.Id) -ForceDeletion $true

    # Checking if the source VM is deleted
    try {
        Get-AzVm -ResourceGroupName $rgName -Name $vmName *>1 | Out-Null
        throw "Source VM is still present. Please select Y on the confirmation prompt"
    }
    catch {
        Write-Host "--> VM successfully deleted"
    }
}

# Recreate the new VM
Write-Host "-> Creating the new VM in Azure"
New-AzVM -VM $vmDestination -ResourceGroupName $rgName -Location $($vmSource.Location) | Out-Null
Write-Host "--> New VM $vmName successfully created!"