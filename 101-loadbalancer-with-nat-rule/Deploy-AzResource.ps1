[CmdletBinding()]
param
(
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, # Resource Group Name

    [parameter(Mandatory = $true)]
    [string] $Location, # Location for all resources.

    [parameter(Mandatory = $false)]
    [string] $AddressPrefix = '10.0.0.0/16', # VNet Address Space

    [parameter(Mandatory = $false)]
    [string] $SubnetPrefix = '10.0.0.0/24', # Subnet Address Prefix

    [parameter(Mandatory = $true)]
    [string] $DNSNameforLBIP, # Unique DNS name

    [Parameter(Mandatory = $false)]
    [ValidateSet('Dynamic', 'Static')]
    [string] $PublicIPAddressType = 'Dynamic' # Public IP type
)

# Declaring local variables
$VirtualNetworkName = "VirtualNetwork1"
$PublicIPAddressName = "PublicIp1"
$SubnetName = "Subnet1"
$LoadBalancerName = "LoadBalancer1"
$NicName = "NetworkInterface1"

# Supress the warning messages
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

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSNameforLBIP

    # Create Virtual Network with subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create LoadBalancer
    $LBFrontendIPConfig = New-AzLoadBalancerFrontendIpConfig -Name LoadBalancerFrontend -PublicIpAddressId $PublicIpAddress.Id
    $LBBackendAddressPool = New-AzLoadBalancerBackendAddressPoolConfig -Name LoadBalancerBackEnd
    $NATRule = New-AzLoadBalancerInboundNatRuleConfig -Name RDP -FrontendIpConfigurationId $LBFrontendIPConfig.Id -Protocol Tcp -FrontendPort 3389 -BackendPort 3389 
    $null = New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LoadBalancerName -Location $Location -FrontendIpConfiguration $LBFrontendIPConfig -BackendAddressPool $LBBackendAddressPool -InboundNatRule $NATRule

    # Create Network Interface Card with load balancer
    $NICConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -SubnetId $VirtualNetwork.Subnets[0].Id -LoadBalancerBackendAddressPoolId $LBBackendAddressPool.Id -LoadBalancerInboundNatRuleId $NATRule.Id
    $null = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICName -IpConfiguration $NICConfig

    # Deployment status
    $DeployStatus = $true
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
    { Write-Host -ForegroundColor Green "Deployment is successful!" }
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}