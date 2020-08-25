[CmdletBinding()]
param
(
    # Resource Group Name
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location, 

    # The name of the VM
    [parameter(Mandatory = $true)]
    [string] $VMName,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # Unique public DNS prefix for the deployment. The fqdn will look something like '<dnsname>.westus.cloudapp.azure.com'. 
    # Up to 62 chars, digits or dashes, lowercase, should start with a letter: must conform to '^[a-z][a-z0-9-]{1,61}[a-z0-9]$'.
    [Parameter(Mandatory = $true)]
    [string] $DNSLabelPrefix,

    # Public port number for RDP
    [Parameter(Mandatory = $false)]
    [int] $RDPPort = 50001
)

# Declare local variables
$StorageAccountName = ('sardpvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$VirtualNetworkName = 'rdpVNET'
$VNetAddressRange = '10.0.0.0/16'
$SubnetAddressRange = '10.0.0.0/24'
$SubnetName = 'Subnet'
$ImagePublisher = 'MicrosoftWindowsServer'
$ImageOffer = 'WindowsServer'
$ImageSku = '2012-R2-Datacenter'
$NetworkSecurityGroupName = 'Subnet-nsg'

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

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name publicIp `
        -AllocationMethod Dynamic -DomainNameLabel $DNSLabelPrefix

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName Standard_LRS

    # Create Network Security Group with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name default-allow-3389 -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressRange -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $VNetAddressRange -Subnet $Subnet

    # Create LoadBalancer
    $LBFrontendIPConfig = New-AzLoadBalancerFrontendIpConfig -Name LBFE -PublicIpAddressId $PublicIpAddress.Id
    $LBBackendAddressPool = New-AzLoadBalancerBackendAddressPoolConfig -Name LBBAP
    $NATRule = New-AzLoadBalancerInboundNatRuleConfig -Name rdp -FrontendIpConfigurationId $LBFrontendIPConfig.Id -Protocol Tcp -FrontendPort 3389 -BackendPort 3389 
    $null = New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name loadBalancer -Location $Location -FrontendIpConfiguration $LBFrontendIPConfig -BackendAddressPool $LBBackendAddressPool -InboundNatRule $NATRule

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig -SubnetId $VirtualNetwork.Subnets[0].Id -LoadBalancerBackendAddressPoolId $LBBackendAddressPool.Id -LoadBalancerInboundNatRuleId $NATRule.Id
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $("{0}-nic" -f $VMName.ToLower()) -IpConfiguration $NetworkInterfaceIPConfig

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize Standard_A0
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSku -Version latest
    
    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

    # Enable Boot Diagnostics
    $null = $VMConfig | Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -Enable -StorageAccountName $StorageAccountName

    # Create Virtual Machine
    $DeployStatus = (New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig).IsSuccessStatusCode

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
