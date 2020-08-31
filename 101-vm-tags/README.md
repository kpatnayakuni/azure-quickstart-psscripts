101-vm-tags
===
Simple deployment of a VM with Tags
---

## Description

This is a conversion of ARM template [101-vm-tags](https://github.com/Azure/azure-quickstart-templates/tree/master/101-vm-tags) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script.

This script allows you to deploy a simple Windows VM using a few different options for the Windows version, using the latest patched version. This will include tags on the Virtual Machine, Storage Account, Public IP Address, Virtual Network, and Network Interface, and it will deploy the following resources...

![image](resources.png)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If the specified resource group is already exist then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResource.ps1 [-ResourceGroupName] <string> [-Location] <string> [-AdminCredential] <pscredential> [[-DNSLabelPrefix] <string>] [[-WindowsOSVersion] <string>] [[-DepartmentName] <string>] [[-ApplicationName] <string>] [[-CreatedBy] <string>] [[-VMSize] <string>] [<CommonParameters>]
```

## Example
```powershell
I 💙 PS> $Credential = Get-Credentials

PowerShell credential request
Enter your credentials.
User: sysadmin
Password for user sysadmin: *************

I 💙 PS> $param = @{
>> ResourceGroupName = 'test-rg'
>> Location = 'westus'
>> AdminCredential = $Credential
>> }

I 💙 PS> .\Deploy-AzResources.ps1 @param
```

## Output
```
Deployment is successful!
```

> Azure Cloud Shell comes with Azure PowerShell pre-installed and you can deploy the above resources using Cloud Shell as well.
>
>[![](https://shell.azure.com/images/launchcloudshell.png "Launch Azure Cloud Shell")](https://shell.azure.com)

Thank you.
