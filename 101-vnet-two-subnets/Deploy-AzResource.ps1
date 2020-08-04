[CmdletBinding()]
param
(
    # Resource Group Name
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location, 

    # Virtual Network Name
    [Parameter(Mandatory = $false)]
    [string] $VNetName = 'VNet1',

    # Virtual Network Address Space
    [Parameter(Mandatory = $false)]
    [string] $VNetAddressSpace = '10.0.0.0/16',
    
    # Subnet 1 Name
    [Parameter(Mandatory = $false)]
    [string] $Subnet1Name = 'Subnet1',
    
    # Subnet 1 address prefix
    [Parameter(Mandatory = $false)]
    [string] $Subnet1Prefix = '10.0.0.0/24',
    
    # Subnet 2 Name
    [Parameter(Mandatory = $false)]
    [string] $Subnet2Name = 'Subnet2',
    
    # Subnet 2 address prefix
    [Parameter(Mandatory = $false)]
    [string] $Subnet2Prefix = '10.0.1.0/24'
)

# Supress the warning messages
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

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

    # Create subnet 1
    $Subnet1 = New-AzVirtualNetworkSubnetConfig -Name $Subnet1Name -AddressPrefix $Subnet1Prefix 

    # Create subnet 2
    $Subnet2 = New-AzVirtualNetworkSubnetConfig -Name $Subnet2Name -AddressPrefix $Subnet2Prefix 

    # Create Virtual Network with 2 subnets
    $null = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VNetName -AddressPrefix $VNetAddressSpace -Subnet $Subnet1, $Subnet2

    # Deployment status
    $DeployStatus = $?
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution failed, cleaning the deployment..." -ForegroundColor Red
    $DeployStatus = $false
    $null = Remove-AzResourceGroup -Name $ResourceGroupName -Force 
}
finally
{
    # Display the deployment status
    if ($DeployStatus) 
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!"
    }
    else 
    { 
        Write-Host -ForegroundColor Red "Deployment is unsuccessful!" 
    }
}