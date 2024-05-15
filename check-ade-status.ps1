# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

Write-Host "-> Checking ADE status for vm $vmName"
# Get current ADE status
$adeStatus = Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName
Write-Host "--> OsVolumeEncrypted=$($adeStatus.OsVolumeEncrypted)"
Write-Host "--> DataVolumesEncrypted=$($adeStatus.DataVolumesEncrypted)"
Write-Host "--> ProgressMessage=$($adeStatus.ProgressMessage)"

# If encryption is enabled on the OSDisk
if ($adeStatus.OsVolumeEncrypted -eq "Encrypted") {
    Write-Host "-> VM is encrypted with ADE"
}
else {
    Write-Host "-> VM is not encrypted with ADE"
}
