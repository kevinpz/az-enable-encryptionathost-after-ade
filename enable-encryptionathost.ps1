# Load the env variable
. ".\env.ps1"

# Select to the subscription
Set-AzContext -Subscription $subscriptionName | Out-Null

# Checking powerstate
Write-Host "-> Checking VM power state"
$vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
$powerState = $vm.Statuses[1].Code

if ($powerState -eq "PowerState/running") {
    Write-Host "--> VM is running. VM should be stopped to enable encryption at host. Stopping the VM $vmName..."
    Stop-AzVM -ResourceGroupName $rgName -Name $vmName

    # Checking if the VM is stopped now
    $vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName -Status
    $powerState = $vm.Statuses[1].Code
    if ($powerState -eq "PowerState/running") {
        throw "VM is still running"
    }
}

# Get the VM
Write-Host "-> Getting the VM"
$vm = Get-AzVm -ResourceGroupName $rgName -Name $vmName
 
# Enable Encryption at Host
Write-Host "-> Enabling encryption at host"
Update-AzVM -VM $vm -ResourceGroupName $rgName -EncryptionAtHost $true
Write-Host "--> Encryption at host successfully enabled"