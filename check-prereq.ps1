# Load the env variable
. ".\env.ps1"

# Checking prerequisite
Write-Host "-> Checking prerequisite"

# Check az cmdlet
Write-Host "--> Checking if Azure cmdlet are installed"
try {
    Get-Command Get-AzVm *>&1 | Out-Null
    Write-Host "--> Ok"
}
catch {
    throw "-> Azure cmdlet are NOT installed! Please install them."
}

# Check azcopy
Write-Host "--> Checking if azcopy is installed"
try {
    Get-Command azcopy *>&1 | Out-Null
    Write-Host "--> Ok"
}
catch {
    throw "-> azcopy is NOT installed! Please install it."
}

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Check encryption at host feature
Write-Host "--> Checking if the encryption at host feature is enabled on the subscription"
$encryptionAtHost = Get-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
if ($encryptionAtHost.RegistrationState -eq "Registered") {
    Write-Host "--> Ok"
}
else {
    throw '-> Encryption at host is not enabled on the subscription. Please enable it with the following cmdlet: Register-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"'
}

# Checking if the VM is Windows
Write-Host "--> Checking if the OS is supported to use the scripts"
$vmSource = Get-AzVm -ResourceGroupName $rgName -Name $vmName
$osType = $vmSource.StorageProfile.osDisk.osType
if ($osType -eq "Windows") {
    Write-Host "---> OS $osType is supported"
}
# Disabling OS disk ADE is not supported on Linux, see:
# https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disk-encryption-linux?tabs=azcliazure%2Cenableadecli%2Cefacli%2Cadedatacli#disable-encryption-and-remove-the-encryption-extension
else {
   throw "---> OS $osType is NOT supported! See: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disk-encryption-linux?tabs=azcliazure%2Cenableadecli%2Cefacli%2Cadedatacli#disable-encryption-and-remove-the-encryption-extension"
}