101-sql-database
===
Azure SQL Database
---

## Description

This is a conversion of ARM template [101-sql-database](https://github.com/Azure/azure-quickstart-templates/tree/master/101-sql-database) from the repository [azure\azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) to PowerShell Script.

This script allows you to create Azure SQL Database, and it will deploy the following resources...

![image](resources.png)

... and in-addition to it, just in-case if the deployment is not successful, then it will rollback the entire deployment.

> ### Note: 
> If the specified resource group is already exist then the script will not continue with the deployment.

## Syntax
```
Deploy-AzResource.ps1 [-ResourceGroupName] <string> [-Location] <string> [[-ServerName] <string>] [[-SqlDBName] <string>] [-AdminCredential] <pscredential> [<CommonParameters>]
```

## Example
```powershell
I 💙 PS> $Credential = Get-Credentials

PowerShell credential request
Enter your credentials.
User: sqladmin
Password for user sqladmin: *************

I 💙 PS> $param = @{
>> ResourceGroupName = 'azsqldb-rg'
>> Location = 'westus'
>> AdminCredential = $Credential
>> }

I 💙 PS> .\Deploy-AzResources.ps1 @param
```

## Output
```
Deployment is successful!
Connect SQL Server using sqlo5ckjzma.database.windows.net:1433
```

> Azure Cloud Shell comes with Azure PowerShell pre-installed and you can deploy the above resources using Cloud Shell as well.
>
>[![](https://shell.azure.com/images/launchcloudshell.png "Launch Azure Cloud Shell")](https://shell.azure.com)

Thank you.
