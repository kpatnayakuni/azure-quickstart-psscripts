101-1vm-2nics-2subnets-1vnet
===
Multi-NIC Virtual Machine Creation using Two Subnets
---

## Description

This is a conversion of ARM template [101-1vm-2nics-2subnets-1vnet](https://github.com/Azure/azure-quickstart-templates/tree/master/101-1vm-2nics-2subnets-1vnet) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script, and this script will deploy following the resources...

![image](https://github.com/kpatnayakuni/azure-quickstart-psscripts/blob/master/101-1vm-2nics-2subnets-1vnet/resources.jpg)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If there is already the specified resource group exists then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResources.ps1 [-ResourceGroupName] <string> [-Location] <string> [-AdminUsername] <string> [-AdminPassword] <securestring> [[-StorageAccountType] <string>] [[-VMSize] <string>] [<CommonParameters>]
```
## Example
```powershell
I 💙 PS> $param = @{
>> ResourceGroupName = 'simple-rg'
>> Location = 'westus'
>> AdminUsername = 'sysadmin'
>> StorageAccountType = 'Standard_LRS'
>> }

I 💙 PS> .\Deploy-AzResources.ps1 @param
```
```
cmdlet Deploy-AzResources.ps1 at command pipeline position 1
Supply values for the following parameters:
AdminPassword: *************
Deployment is successful!
HostName: Not Assigned
```

Thank you.
