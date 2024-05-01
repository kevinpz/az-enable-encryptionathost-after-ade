# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null
 
# Disable ADE
Remove-AzVMDiskEncryptionExtension -ResourceGroupName $rgName -VMName $vmName 