# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null
 
# Disable ADE
Disable-AzVMDiskEncryption -ResourceGroupName $rgName -VMName $vmName -VolumeType "all"