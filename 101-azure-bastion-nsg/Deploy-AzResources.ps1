[CmdletBinding()]
param
(
    [parameter(Mandatory, ParameterSetName = 'New')]
    [parameter(Mandatory = $false, ParameterSetName = 'Existing')]
    [string] $ResourceGroupName, # Resource Group Name

    [parameter(Mandatory, ParameterSetName = 'New')]
    [string] $Location, # Location for all resources.

    [parameter(Mandatory, ParameterSetName = 'New')]
    [parameter(Mandatory, ParameterSetName = 'Existing')]
    [ArgumentCompleter( {
            return $(Get-AzVirtualNetwork | ForEach-Object Name)
        })]
    [string] $VNetName, # Select the existing VNet or enter a new VNet name to which Azure Bastion should be deployed

    [parameter(Mandatory, ParameterSetName = 'New')]
    [string] $VNetIPPrefix = '10.1.0.0/16', # IP prefix for available addresses in vnet address space

    [Parameter(Mandatory, ParameterSetName = 'New')]
    [string] $DefaultSubnetIPPrefix = '10.1.0.0/24', # Subnet IP prefix in vnet address space, just in case of a new vnet

    [parameter(Mandatory, ParameterSetName = 'New')]
    [parameter(Mandatory, ParameterSetName = 'Existing')]
    [string] $BastionHostName, # Name of the Azure Bastion resource

    [parameter(Mandatory, ParameterSetName = 'New')]
    [parameter(Mandatory, ParameterSetName = 'Existing')]
    [string] $BastionSubnetIPPrefix  # Bastion subnet IP prefix MUST be within vnet IP prefix address space
)

# Declaring local variables
$PublicIpAddressName = "$BastionHostName-pip"
$BastionSubnetName = "AzureBastionSubnet"
$NsgName = "$BastionHostName-nsg"

# Supress the warning messages
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

try
{
    if ($PSCmdlet.ParameterSetName -eq 'Existing')
    {
        # Get the Virtual Network if it exists
        $VirtualNetwork = Get-AzVirtualNetwork -Name $VNetName
        if (-not $VirtualNetwork) 
        {
            Write-Host "No Virtual Network found with the name $VNetName in the current context, `nTO create new add -Location, -VNetIPPrefix and -DefaultSubnetIPPrefix as well and pass the values." -ForegroundColor Red
            return
        }
        else 
        {
            $Location = $VirtualNetwork.Location    
        }

        # Pull the resource group name and location from the existing VNet if the -ResourceGroupName is not provided
        if (-not $ResourceGroupName) 
        { 
            $ResourceGroupName = $VirtualNetwork.ResourceGroupName
        }
        elseif (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) # Create a new Resource Group if the -ResourceGroupName is provided and doesn't exist in the current context
        {
            # Create Resource Group
            $null = New-AzResourceGroup -Name $ResourceGroupName -Location 
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'New')
    {
        # Create Resource Group
        if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue))
        {
            $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        }

        # Create Virtual Network with default subnet
        $DefaultSubnet = New-AzVirtualNetworkSubnetConfig -Name default -AddressPrefix $DefaultSubnetIPPrefix
        $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VNetName -AddressPrefix $VNetIPPrefix -Subnet $DefaultSubnet    
    }

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIpAddressName -AllocationMethod Static -Sku Standard

    ## Create Network Security Group
    # Inbound Rules
    $NSRule1 = New-AzNetworkSecurityRuleConfig -Name 'bastion-in-allow' -Priority 100 -Access Allow -Direction Inbound -DestinationPortRange 443 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix Internet -DestinationAddressPrefix *
    $NSRule2 = New-AzNetworkSecurityRuleConfig -Name 'bastion-control-in-allow' -Priority 120 -Access Allow -Direction Inbound -DestinationPortRange 443, 4443 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix GatewayManager -DestinationAddressPrefix *
    $NSRule3 = New-AzNetworkSecurityRuleConfig -Name 'bastion-in-deny' -Priority 900 -Access Deny -Direction Inbound -DestinationPortRange * `
        -Protocol * -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *

    # Outbound Rules
    $NSRule4 = New-AzNetworkSecurityRuleConfig -Name 'bastion-vnet-out-allow' -Priority 100 -Access Allow -Direction Outbound -DestinationPortRange 22, 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix VirtualNetwork
    $NSRule5 = New-AzNetworkSecurityRuleConfig -Name 'bastion-azure-out-allow' -Priority 120 -Access Allow -Direction Outbound -DestinationPortRange 443 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix AzureCloud

    # NetworkSecurityGroup
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NsgName -SecurityRules $NSRule1, $NSRule2, $NSRule3, $NSRule4, $NSRule5

    # Add Bastion Subnet to Virtual Network
    $null = Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $BastionSubnetName -AddressPrefix $BastionSubnetIPPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $null = $VirtualNetwork | Set-AzVirtualNetwork

    # Create Bastion Host
    $DeployStatus = New-AzBastion -ResourceGroupName $ResourceGroupName -Name $BastionHostName -PublicIpAddressId $PublicIpAddress.Id -VirtualNetworkId $VirtualNetwork.Id
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host -ForegroundColor Red $_
    if ($PSCmdlet.ParameterSetName -eq 'Existing')
    {
        Write-Host "Execution failed, clean the deployment manually..." -ForegroundColor Red
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'New')
    {
        Write-Host "Execution failed, cleaning the deployment..." -ForegroundColor Red    
        $null = Remove-AzResourceGroup -Name $ResourceGroupName -Force 
    }
    $DeployStatus = $false
}
finally
{
    # Write deployment status
    if ($DeployStatus)
    {
        Write-Host -ForegroundColor Green "$BastionHostName is successfully deployed."
    }
    else 
    {
        Write-Host -ForegroundColor Red "$BastionHostName deployed is unsuccessful."
    }
}
