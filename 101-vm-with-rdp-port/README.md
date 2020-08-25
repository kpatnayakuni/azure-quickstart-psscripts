101-vm-with-rdp-port
===
Create a VM with an RDP port
---

## Description

This is a conversion of ARM template [101-vm-with-standardssd-disk](https://github.com/Azure/azure-quickstart-templates/tree/master/101-vm-with-standardssd-disk) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script.

This script allows you to create a NAT rule in loadbalancer to allow RDP to a vm, and it will deploy the following resources...

![image](resources.png)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If the specified resource group is already exist then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResource.ps1 [-ResourceGroupName] <string> [-Location] <string> [-VMName] <string> [-AdminCredential] <pscredential> [-DNSLabelPrefix] <string> [[-RDPPort] <int>] [<CommonParameters>]
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
>> VMName = 'rdpvm'
>> AdminCredential = $Credential
>> DNSLabelPrefix = 'rdpvmsdjvfsdf'
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
