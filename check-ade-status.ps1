# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null
 
# Disable ADE
Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName