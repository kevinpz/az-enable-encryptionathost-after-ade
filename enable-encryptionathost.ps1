# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Get the VM
Write-Host "Getting the VM"
$vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName
 
# Enable Encryption at Host
Write-Host "-> Enabling encryption at host"
Update-AzVM -VM $vm -ResourceGroupName $rgName -EncryptionAtHost $true