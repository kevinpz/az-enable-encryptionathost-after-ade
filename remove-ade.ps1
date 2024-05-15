# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Checking powerstate
Write-Host "-> Checking VM power state"
$vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
$powerState = $vmSource.Statuses[1].Code

if ($powerState -ne "PowerState/running") {
    Write-Host "--> VM is not running. VM should be running to disable ADE. Starting the VM $vmName..."
    Start-AzVM -ResourceGroupName $rgName -Name $vmName -Confirm

    # Checking if the VM is running now
    $vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
    $powerState = $vmSource.Statuses[1].Code
    if ($powerState -ne "PowerState/running") {
        throw "VM is still not running"
    }
}
 
# Disable ADE
Write-Host "-> Disabling ADE"
Disable-AzVMDiskEncryption -ResourceGroupName $rgName -VMName $vmName -VolumeType "all"

# Get current ADE status
Write-Host "--> Checking the new status"
$adeStatus = Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName
Write-Host "--> OsVolumeEncrypted=$($adeStatus.OsVolumeEncrypted)"
Write-Host "--> DataVolumesEncrypted=$($adeStatus.DataVolumesEncrypted)"
Write-Host "--> ProgressMessage=$($adeStatus.ProgressMessage)"

# If encryption was removed
if ($adeStatus.OsVolumeEncrypted -eq "NotEncrypted") {
    Write-Host "---> ADE successfully disabled!"
    # Remove the extension
    Write-Host "-> Removing the extension"
    Remove-AzVMDiskEncryptionExtension -ResourceGroupName $rgName -VMName $vmName
    Write-Host "--> Extension successfully removed!"
}
else {
    throw "Something went wrong... ADE is still enabled."
}

