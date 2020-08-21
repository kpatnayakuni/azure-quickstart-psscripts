101-vm-simple-windows
===
Very simple deployment of a Windows VM
---

## Description

This is a conversion of ARM template [101-vm-simple-windows](https://github.com/Azure/azure-quickstart-templates/tree/master/101-vm-simple-windows) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script.

This script allows you to deploy a simple Windows VM using a few different options for the Windows version, using the latest patched version. This will deploy a A2 size VM in the resource group location and return the fully qualified domain name of the VM, and it will deploy following the resources...

![image](https://github.com/kpatnayakuni/azure-quickstart-psscripts/blob/master/101-vm-simple-windows/resources.png)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If there is already the specified resource group exists then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResources.ps1 [-resourceGroupName] <string> [-location] <string> [-adminUsername] <string> [-adminPassword] <securestring> [-dnsLabelPrefix] <string> [[-windowsOSVersion] <string>] [[-vmSize] <string>] [<CommonParameters>]
```
## Example
```powershell
I 💙 PS> $param = @{
>> resourceGroupName = 'simple-rg'
>> location = 'westus'
>> adminUsername = 'sysadmin'
>> dnsLabelPrefix = 'patnayakuni1981'
>> }

I 💙 PS> .\Deploy-AzResources.ps1 @param
```

## Output
```
cmdlet Deploy-AzResources.ps1 at command pipeline position 1
Supply values for the following parameters:
adminPassword: *************
Deployment is successful!
HostName: patnayakuni1981.westus.cloudapp.azure.com
```

> Azure Cloud Shell comes with Azure PowerShell pre-installed and you can deploy the above resources using Cloud Shell as well.
>
>[![](https://shell.azure.com/images/launchcloudshell.png "Launch Azure Cloud Shell")](https://shell.azure.com)

Thank you.
