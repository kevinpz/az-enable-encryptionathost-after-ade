# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Get the VM
Write-Host "-> Finding the source VM"
$vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName
Write-Host "-> Finding the duplicate VM"
$vmDuplicate = Get-AzVm -ResourceGroupName $rgName -Name "$($vm.Name)_noade"

# Update deleteoption properties
Write-Host "-> Updating the delete behavior on the source VM (keep everything)"
$vmSource.StorageProfile.OsDisk.DeleteOption = 'Detach'
$vmSource.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Detach' }
$vmSource.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Detach' }
$vmSource | Update-AzVM

Write-Host "-> Updating the delete behavior on the duplicate VM (don't keep the temp NIC)"
$vmDuplicate.StorageProfile.OsDisk.DeleteOption = 'Detach'
$vmDuplicate.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Detach' }
$vmDuplicate.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Delete' }
$vmDuplicate | Update-AzVM

# Get the VM information
$osDiskName = $vmDuplicate.StorageProfile.OsDisk.Name
$nicId = $vmSource.NetworkProfile.NetworkInterfaces[0].Id
[Array]$vmDataDisk = $()
$vmDuplicate.StorageProfile.DataDisks | foreach { 
    $vmDataDisk += @{Name=$_.Name; Lun=$($_.Lun)}
}

Write-Host "-> DEBUG INFO"
Write-Host "Location = $($vm.Location)"
Write-Host "OS DISK = $osDiskName"
Write-Host "DATA DISKS = $vmDataDisk"
Write-Host "NIC = $nicId"

# Delete the source VM and the duplicate VM
Write-Host "-> Removing the duplicate VM"
#Remove-AzVm -VM $vmDuplicate -ResourceGroupName $rgName -ForceDeletion $true
Write-Host "-> Removing the source VM"
#Remove-AzVm -VM $vmSource -ResourceGroupName $rgName -ForceDeletion $true

# Create the new VM object
# Remove some parameters not needed for the creation
Write-Host "-> Creating the new VM config"
$newVm = $vm | Select-Object -Property * -ExcludeProperty Id, VmId, ProvisioningState, RequestId, StatusCode, ResourceGroupName, TimeCreated, OsProfile
$newVm.StorageProfile = $vm.StorageProfile | Select-Object -Property * -ExcludeProperty ImageReference

# Set the VM configuration to point to the new disk  
Write-Host "--> Swapping the VM OS disk"
Set-AzVMOSDisk -VM $newVm -Name $osDiskName -CreateOption Attach | Out-Null

# Duplicate all the data disks
$vmDataDisk | foreach { 
    # If we have data disk
    if ($_) {
        # Attach the new data disk to the vm with the same LUN
        Write-Host "--> Attaching the new data disk $($newDisk.Name)"
        Add-AzVMDataDisk -VM $newVm -Name $($_.Name) -CreateOption Attach -Lun $($_.Lun) | Out-Null
    }
}

# Adding the source NIC to the new VM
Add-AzVMNetworkInterface -VM $newVm -Id $nicId | Out-Null

Write-Host "-> Creating the new VM"
#New-AzVM -VM $newVm -ResourceGroupName $rgName -Location $($vm.Location) | Out-Null
