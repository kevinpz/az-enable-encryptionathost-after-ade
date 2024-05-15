param (
  [switch] $LoadFromFile
)

# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

if (-Not($LoadFromFile)) {
    # Get the VM
    Write-Host "-> Finding the source VM"
    $vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName
    Write-Host "-> Finding the duplicate VM"
    $vmDuplicate = Get-AzVm -ResourceGroupName $rgName -Name "$($vmSource.Name)_noade"

    # Update deleteoption properties
    Write-Host "-> Updating the delete behavior on the source VM (keep everything)"
    $vmSource.StorageProfile.OsDisk.DeleteOption = 'Detach'
    $vmSource.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Detach' }
    $vmSource.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Detach' }
    $vmSource | Update-AzVM | Out-Null

    Write-Host "-> Updating the delete behavior on the duplicate VM (don't keep the temp NIC)"
    $vmDuplicate.StorageProfile.OsDisk.DeleteOption = 'Detach'
    $vmDuplicate.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Detach' }
    $vmDuplicate.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Delete' }
    $vmDuplicate | Update-AzVM | Out-Null

    # Saving the original VM object to the disk, just in case ...
    Write-Host "-> Saving the VM config to file just in case :)"
    $vmSource | Export-Clixml sourceVm.xml -Depth 20
    $vmDuplicate | Export-Clixml duplicateVm.xml -Depth 20

    Write-Host "-> If the script fails for whatever reason after the VM deletion ..."
    Write-Host "-> Use the following parameters to start it:"
    Write-Host "pwsh replace-vm.ps1 -LoadFromFile"

    # Delete the source VM and the duplicate VM
    Write-Host "-> Removing the duplicate VM $($vmDuplicate.Id)"
    #Remove-AzVm -Id $($vmDuplicate.Id) -ForceDeletion $true
    Write-Host "-> Removing the source VM $($vmSource.Id)"
    #Remove-AzVm -Id $($vmSource.Id) -ForceDeletion $true
}
else {
    Write-Host "-> Loading source and duplicate config VM from file"
    $vmSource=Import-Clixml -Path sourceVm.xml
    $vmDuplicate=Import-Clixml -Path duplicateVm.xml
}

# Get the VM information
$osDiskName = $vmDuplicate.StorageProfile.OsDisk.Name
$nicId = $vmSource.NetworkProfile.NetworkInterfaces[0].Id

# Create the new VM object
Write-Host "-> Creating the new VM config"
$newVm = New-AzVMConfig -VMName $($vmSource.Name) -VMSize $($vmSource.HardwareProfile.VmSize) -Tags $($vmSource.Tags)
$newVm.SecurityProfile = $vmSource.SecurityProfile
if($vm.LicenseType) {
    $newVm.LicenseType = $vm.LicenseType
}
$newVm.Tags = $vmSource.Tags
$newVm.DiagnosticsProfile = $vmSource.DiagnosticsProfile
$newVm.AdditionalCapabilities = $vmSource.AdditionalCapabilities
###TODO $newVm.Identity = $vmSource.Identity

# Set the VM configuration to point to the new disk  
Write-Host "--> Setting the VM OS disk"
Set-AzVMOSDisk -VM $newVm -Name $osDiskName -CreateOption Attach | Out-Null

# Duplicate all the data disks
$vmDuplicate.StorageProfile.DataDisks | foreach { 
    # If we have data disk
    if ($_) {
        # Attach the new data disk to the vm with the same LUN
        Write-Host "--> Attaching the new data disk $($newDisk.Name)"
        Add-AzVMDataDisk -VM $newVm -Name $($_.Name) -CreateOption Attach -Lun $($_.Lun) | Out-Null
    }
}

# Adding the source NIC to the new VM
Add-AzVMNetworkInterface -VM $newVm -Id $nicId | Out-Null

# Setting the OS type disk
$newVm.StorageProfile.osDisk.osType = $vm.StorageProfile.osDisk.osType

Write-Host "-> Creating the new VM"
$newVm
New-AzVM -VM $newVm -ResourceGroupName $rgName -Location $($vmSource.Location) | Out-Null
