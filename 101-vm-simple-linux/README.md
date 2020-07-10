101-vm-simple-linux
===
Very simple deployment of a Linux VM
---

## Description

This is a conversion of ARM template [101-vm-simple-linux](https://github.com/Azure/azure-quickstart-templates/tree/master/101-vm-simple-linux) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script, and this script will deploy following the resources...

![image](https://github.com/kpatnayakuni/azure-quickstart-psscripts/blob/master/101-vm-simple-linux/resources.jpg)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If there is already the specified resource group exists then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResources.ps1 [-resourceGroupName] <string> [-location] <string> [-adminUsername] <string> [[-authenticationType] <string>] [-adminPassword] <securestring> [[-KeyFileName] <string>] [-dnsLabelPrefix] <string> [[-ubuntuOSVersion] <string>] [<CommonParameters>]
```
## Example

### Deploy a linux VM with username and password

```powershell
I 💙 PS> $param = @{
>> resourceGroupName = 'simple-rg'
>> location = 'westus'
>> adminUsername = 'sysadmin'
>> authenticationType = 'password'
>> dnsLabelPrefix = 'patnayakuni1981'
>> ubuntuOSVersion = '18.04-LTS'
>> }

I 💙 PS> .\Deploy-AzResources.ps1 @param
```
```
cmdlet Deploy-AzResources.ps1 at command pipeline position 1
Supply values for the following parameters:
(Type !? for Help.)
adminPassword: *************
Deployment is successful!
HostName: patnayakuni1981.westus.cloudapp.azure.com
```

Thank you.
