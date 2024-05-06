# az-enable-encryptionathost-after-ade
Enable encryption at host on an Azure VM with ADE enabled.

> [!CAUTION]
> The scripts provided in this repository are for example purposes only and are not supported by Microsoft. They are offered as-is, without warranty, and users should use them at their own risk. Please review the code thoroughly to ensure it meets your needs before using it in a production environment. Microsoft or the author do not assume any liability for any damages or losses incurred from using these scripts.

## Limitation
> [!IMPORTANT]  
> These scripts only work for Windows VM.

## Why
If you try to enable encryption at host after disabling ADE on a VM, you'll get the following error message:
```
Failed to update 'vm-test-encryption'. Error: Encryption at host is not allowed for a VM having disks that were encrypted with Azure Disk Encryption
```

## Prerequisites
* Powershell with the Azure cmdlet installed
* Azcopy installed
* Setup the parameters in the `env.ps1` file
* Encryption at host feature should be registered on the subscription

## How to
In order to enable encryption at host on a VM already encrypted with ADE you need to follow these steps:
* Disable ADE
* Remove the ADE extension
* Create a new disk to copy the data from the old disk to the new disk (this step is mandatory otherwise you won't be able to enable encryption at host on a disk were ADE was previously enabled)
* Attach the new disk to the VM
* Enable encryption at host


```ps1
# Mandatory information
$subscriptionName = "<Subscription Name>"
$rgName = "<Rg Name>"
$vmName = "<VM Name>"
```

## Steps
### Check if ADE is enabled
To check if ADE is enabled on the VM:
```bash
pwsh check-ade-status.ps1
```

Output if it's **disabled**:
```
OsVolumeEncrypted          : NotEncrypted
DataVolumesEncrypted       : NotEncrypted
OsVolumeEncryptionSettings :
ProgressMessage            : Extension status not available on the VM
```

Output if it's **enabled**:
```
OsVolumeEncrypted          : Encrypted
DataVolumesEncrypted       : Encrypted
OsVolumeEncryptionSettings : Microsoft.Azure.Management.Compute.Models.DiskEncr
                             yptionSettings
ProgressMessage            : [2.4.0.21]
```

### Disable ADE
> [!WARNING]  
> Be aware than disable ADE may reboot the VM
```
This cmdlet disables encryption on the VM which may reboot the machine. Please
save your work on the VM before confirming. Do you want to continue?
```

If ADE is enabled, execute the following command to disable it:
```bash
pwsh disable-ade.ps1
```

Then check if ADE was successfully removed:
```bash
pwsh check-ade-status.ps1

OsVolumeEncrypted          : NotEncrypted
DataVolumesEncrypted       : NotEncrypted
OsVolumeEncryptionSettings :
ProgressMessage            : [2.4.0.21] Disable Encryption completed
                             successfully
```

### Remove ADE extension
Once the VM encryption is disabled, you can remove the extension:
```bash
pwsh remove-extension.ps1
```

### Create a new disk with the old data
Directly duplicating the disk, or using a snapshot won't allow encryption at host to be enable. You need to create a new disk and transfer the data from the old one.

> [!IMPORTANT]  
> Stop the VM first

You can run this command to do the start the process:
```bash
pwsh replace-disk.ps1
```

Command return:
```
Finding the VM
-> OS Disk
--> Duplicating the OS disk vm-test-encryption_OsDisk_1_345eacc4104d46e396d987af3a9d6aa5
---> Getting the VM old disk informations
---> Creating the new disk config
---> Creating the disk in Azure
---> Getting a read SAS token for the old disk
---> Getting a write SAS token for the new disk
---> Running azcopy to transfer the data (this may take a while)
---> Removing the SAS token for the old disk
---> Removing the SAS token for the new disk
------> New disk info
--> Swapping the VM OS disk
--> Updating the VM config
-> Data Disks
--> Duplicating the data disk vm-test-encryption_DataDisk_0
---> Getting the VM old disk informations
---> Creating the new disk config
---> Creating the disk in Azure
---> Getting a read SAS token for the old disk
---> Getting a write SAS token for the new disk
---> Running azcopy to transfer the data (this may take a while)
---> Removing the SAS token for the old disk
---> Removing the SAS token for the new disk
--> Removing the old data disk vm-test-encryption_DataDisk_0
--> Updating the VM config
--> Attaching the new data disk vm-test-encryption_DataDisk_0_noade
--> Updating the VM config
--> Duplicating the data disk vm-test-encryption_DataDisk_1
---> Getting the VM old disk informations
---> Creating the new disk config
---> Creating the disk in Azure
---> Getting a read SAS token for the old disk
---> Getting a write SAS token for the new disk
---> Running azcopy to transfer the data (this may take a while)
---> Removing the SAS token for the old disk
---> Removing the SAS token for the new disk
--> Removing the old data disk vm-test-encryption_DataDisk_1
--> Updating the VM config
--> Attaching the new data disk vm-test-encryption_DataDisk_1_noade
--> Updating the VM config
```

### Enable encryption at host
> [!IMPORTANT]  
> Stop the VM first

Once the new disk are in place, you can enable encryption at host
```bash
pwsh enable-encryptionathost.ps1
```