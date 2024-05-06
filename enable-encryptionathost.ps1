# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null
 
# Enable Encryption at Host
Update-AzVM -VM $VM -ResourceGroupName $ResourceGroupName -EncryptionAtHost $true