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
Failed to update 'vm-test-ade'. Error: Encryption at host is not allowed for a VM having disks that were encrypted with Azure Disk Encryption
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
* Create a new OS disk and optional data disk(s)
* Copy the data from the old disk(s) to the new disks(s) (this step is mandatory otherwise you won't be able to enable encryption at host on a disk were ADE was previously enabled)
* Delete the old VM and create a new one from the new disk(s)
* Enable encryption at host

## Steps

### Enter required information
Edit the file `env.ps1` with the information of the VM:

```bash
# Mandatory information
$subscriptionName = "<Subscription Name>"
$rgName = "<Rg Name>"
$vmName = "<VM Name>"
```

### Check prerequisite
To check if all the prerequisite are present:
```bash
pwsh check-prereq.ps1
```

Output if everything is **correct**:
```
-> Checking prerequisite
--> Checking if Azure cmdlet are installed
--> Ok
--> Checking if azcopy is installed
--> Ok
--> Checking if the encryption at host feature is enabled on the subscription
--> Ok
--> Checking if the OS is supported to use the scripts
---> OS Windows is supported
```

Output in case of an **error**:
```
-> Checking prerequisite
--> Checking if Azure cmdlet are installed
--> Ok
--> Checking if azcopy is installed
--> Ok
--> Checking if the encryption at host feature is enabled on the subscription
--> Ok
--> Checking if the OS is supported to use the scripts
Exception: /Users/kevin/Documents/CODE/az-enable-encryptionathost-after-ade/check-prereq.ps1:51
Line |
  51 |     throw "---> OS $osType is NOT supported!\n See: https://learn.micr …
     |     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | ---> OS Linux is NOT supported! See:
     | https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disk-encryption-linux?tabs=azcliazure%2Cenableadecli%2Cefacli%2Cadedatacli#disable-encryption-and-remove-the-encryption-extension
```

### Check if ADE is enabled
To check if ADE is enabled on the VM:
```bash
pwsh check-ade-status.ps1
```

Output if it's **disabled**:
```
-> Checking ADE status for vm vm-test-ade
--> OsVolumeEncrypted=NotEncrypted
--> DataVolumesEncrypted=NotEncrypted
--> ProgressMessage=No Encryption extension or metadata found on the VM
-> VM is not encrypted with ADE
```

Output if it's **enabled**:
```
-> Checking ADE status for vm vm-test-ade
--> OsVolumeEncrypted=Encrypted
--> DataVolumesEncrypted=Encrypted
--> ProgressMessage=[2.4.0.23]
-> VM is encrypted with ADE
```

### Disable ADE
> [!IMPORTANT]  
> Be aware that disabling ADE may reboot the VM
```
This cmdlet disables encryption on the VM which may reboot the machine. Please
save your work on the VM before confirming. Do you want to continue?
```

If ADE is enabled, execute the following command to disable it:
```bash
pwsh remove-ade.ps1
```

Expected output:
```
-> Checking VM power state
-> Disabling ADE
--> Checking the new status
--> OsVolumeEncrypted=NotEncrypted
--> DataVolumesEncrypted=NotEncrypted
--> ProgressMessage=[2.4.0.23] Disable Encryption completed successfully
---> ADE successfully disabled!
-> Removing the extension
--> Extension successfully removed!
```

### Replace the VM
Directly duplicating the disk, or using a snapshot won't allow encryption at host to be enable. You need to create a new disk and transfer the data from the old one. The VM object also needs to be recreated in Azure by deleting the source VM and creating a new one.

> [!IMPORTANT]  
> The source VM disk(s) will be preserved. A new OS disk and data disk(s) will be created with the suffix `_noade`.
> The source VM NIC(s) will be preserved and reattached to the new VM.

You can run this command to start the process:
```bash
pwsh replace-vm.ps1
```

Expected output:
```
-> Finding the source VM
--> Source VM found in Azure
-> Checking VM power state
-> Updating the delete behavior on the source VM vm-test-ade (keep everything)
-> Saving the VM config to file, just in case :)
-> Creating the new VM config
-> Attaching the NIC(s) to the new VM
--> Attaching the NIC: vm-test-ade529
-> Duplicating the disks
--> OS Disk
---> Duplicating the OS disk vm-test-ade_OsDisk_1_032397e742ec41529803f28bad9f2821
----> Getting the VM old disk informations
----> Creating the new disk config
----> Creating the disk in Azure
----> Getting a read SAS token for the old disk
----> Getting a write SAS token for the new disk
----> Running azcopy to transfer the data (this may take a while)
----> Removing the SAS token for the old disk
----> Removing the SAS token for the new disk
---> Setting the VM OS disk
--> Data Disks
---> Duplicating the data disk vm-test-ade_DataDisk_0
----> Getting the VM old disk informations
----> Creating the new disk config
----> Creating the disk in Azure
----> Getting a read SAS token for the old disk
----> Getting a write SAS token for the new disk
----> Running azcopy to transfer the data (this may take a while)
----> Removing the SAS token for the old disk
----> Removing the SAS token for the new disk
---> Attaching the new data disk vm-test-ade_DataDisk_0_noade
---> Duplicating the data disk vm-test-ade_DataDisk_1
----> Getting the VM old disk informations
----> Creating the new disk config
----> Creating the disk in Azure
----> Getting a read SAS token for the old disk
----> Getting a write SAS token for the new disk
----> Running azcopy to transfer the data (this may take a while)
----> Removing the SAS token for the old disk
----> Removing the SAS token for the new disk
---> Attaching the new data disk vm-test-ade_DataDisk_1_noade
-> Removing the source VM /subscriptions/570496f6-7110-44f4-bf19-e2ae12fab413/resourceGroups/rg-ade-test/providers/Microsoft.Compute/virtualMachines/vm-test-ade
--> VM successfully deleted
-> Creating the new VM in Azure
--> New VM vm-test-ade successfully created
```

In case something went wrong after the deletion of the source VM, you can restart the script, it'll use the config saved on a file to reload the parameters. In that case you can expect an output like:
```
-> Finding the source VM
--> Can't find the source VM in Azure anymore, loading source VM config from file
-> Creating the new VM config
-> Attaching the NIC to the new VM
--> Attaching the NIC: vm-test-ade529
-> Duplicating the disks
--> OS Disk
---> Duplicating the OS disk vm-test-ade_OsDisk_1_032397e742ec41529803f28bad9f2821
----> Getting the VM old disk informations
----> Duplicate disk already exists
---> Setting the VM OS disk
--> Data Disks
---> Duplicating the data disk vm-test-ade_DataDisk_0
----> Getting the VM old disk informations
----> Duplicate disk already exists
---> Attaching the new data disk vm-test-ade_DataDisk_0_noade
---> Duplicating the data disk vm-test-ade_DataDisk_1
----> Getting the VM old disk informations
----> Duplicate disk already exists
---> Attaching the new data disk vm-test-ade_DataDisk_1_noade
-> Creating the new VM in Azure
--> New VM vm-test-ade successfully created
```

### Enable encryption at host
> [!IMPORTANT]  
> Be aware that to enable encryption at the host, the VM will be stopped.

Once the new VM is created, you can enable encryption at host.
```bash
pwsh enable-encryptionathost.ps1
```

Expected output:
```
-> Checking VM power state
-> Getting the VM
-> Enabling encryption at host
--> Encryption at host successfully enabled
```