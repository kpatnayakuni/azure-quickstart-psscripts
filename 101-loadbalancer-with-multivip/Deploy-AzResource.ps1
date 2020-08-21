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
$PublicIPAddressName1 = "PublicIp1"
$PublicIPAddressName2 = "PublicIp2"
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

    # Create Public IP Address 1
    $PublicIpAddress1 = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName1 -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSNameforLBIP

    # Create Public IP Address 2
    $PublicIpAddress2 = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName2 -AllocationMethod $PublicIPAddressType

    # Create Virtual Network with subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create LoadBalancer
    $LBFrontendIPConfig1 = New-AzLoadBalancerFrontendIpConfig -Name LoadBalancerFrontend1 -PublicIpAddressId $PublicIpAddress1.Id
    $LBFrontendIPConfig2 = New-AzLoadBalancerFrontendIpConfig -Name LoadBalancerFrontend2 -PublicIpAddressId $PublicIpAddress2.Id
    $LBBackendAddressPool = New-AzLoadBalancerBackendAddressPoolConfig -Name LoadBalancerBackEnd
    $LBProbe = New-AzLoadBalancerProbeConfig -Name TCPProbe -Protocol Tcp -Port 445 -IntervalInSeconds 5 -ProbeCount 2
    $LBRule1 = New-AzLoadBalancerRuleConfig -Name LBRuleForVIP1 -FrontendIpConfigurationId $LBFrontendIPConfig1.Id -BackendAddressPoolId $LBBackendAddressPool.Id -ProbeId $LBProbe.Id -Protocol Tcp -FrontendPort 443 -BackendPort 443
    $LBRule2 = New-AzLoadBalancerRuleConfig -Name LBRuleForVIP2 -FrontendIpConfigurationId $LBFrontendIPConfig2.Id -BackendAddressPoolId $LBBackendAddressPool.Id -ProbeId $LBProbe.Id -Protocol Tcp -FrontendPort 443 -BackendPort 444
    $null = New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LoadBalancerName -Location $Location -FrontendIpConfiguration $LBFrontendIPConfig1, $LBFrontendIPConfig2 -BackendAddressPool $LBBackendAddressPool -LoadBalancingRule $LBRule1, $LBRule2 -Probe $LBProbe

    # Create Network Interface Card with load balancer
    $NICConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -SubnetId $VirtualNetwork.Subnets[0].Id -LoadBalancerBackendAddressPoolId $LBBackendAddressPool.Id
    $null = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NicName -IpConfiguration $NICConfig

    # Deployment status
    $DeployStatus = $true
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution is failed with the following error, and cleaning the deployment..." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
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