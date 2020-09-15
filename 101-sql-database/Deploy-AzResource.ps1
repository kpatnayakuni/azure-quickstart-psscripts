[CmdletBinding()]
param
(
    # Resource Group Name
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location, 

    # Sql Server Name
    [Parameter(Mandatory = $false)]
    [string] $ServerName = -join ('sql', $( -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ }))),

    # Sql database name
    [Parameter(Mandatory = $false)]
    [string] $SqlDBName = 'SampleDB',

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential
)

# Supress the warning messages and stop the script on error
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

# Break the script if the resource group is already exists
if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) 
{
    Write-Error -Message "Cannot continue with this deployment since the '$ResourceGroupName' resource group is already exists."
    return
}

try 
{
    # Create Resource Group
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location

    # Create a server with a system wide unique server name
    $SqlServer = New-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $ServerName -Location $Location -SqlAdministratorCredentials $AdminCredential

    # Create a blank database with an S0 performance level
    $DeployStatus = New-AzSqlDatabase  -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $SqlDBName -RequestedServiceObjectiveName "S0" 
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution is failed with the following error, and cleaning the deployment..." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $null = Remove-AzResourceGroup -Name $ResourceGroupName -Force 
    $DeployStatus = $false
}
finally
{
    # Display the deployment status
    if ($DeployStatus) 
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!"
        # Print Sql Server FQDN to connect to the server
        Write-Host ("Connect SQL Server using {0},1433" -f $SqlServer.FullyQualifiedDomainName)
    }
    else 
    { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}