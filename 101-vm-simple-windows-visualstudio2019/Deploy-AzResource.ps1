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
    [parameter(Mandatory = $false)]
    [string] $VMName = 'simpleWinVS',

    # The size of the VM
    [parameter(Mandatory = $false)]
    [string] $VMSize = 'Standard_D2_V2',

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [Parameter(Mandatory = $false)]
    [string] $DNSLabelPrefix = ('simplewinvs-', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join '',

    # Specify whether to create a new or existing NSG and vNet.
    [Parameter(Mandatory = $false)]
    [ValidateSet('New', 'Existing')]
    [string] $SharedResources = 'New',

    # Name of the VNET
    [Parameter(Mandatory = $false)]
    [string] $VirtualNetworkName = 'vNet',

    # Name of the subnet in the virtual network
    [Parameter(Mandatory = $false)]
    [string] $SubnetName = 'Subnet',

    # Name of the Network Security Group
    [Parameter(Mandatory = $false)]
    [string] $NetworkSecurityGroupName = 'SecGroupNet'
)

# Declare local variables
$PublicIpAddressName = "{0}PublicIP" -f $VMName
$NetworkInterfaceName = "{0}NetInt" -f $VMName
$OSDiskType = 'Standard_LRS'
$SubnetAddressPrefix = '10.1.0.0/24'
$AddressPrefix = '10.1.0.0/16'

# Supress the warning messages and stop the script on error
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

try
{
    # Create Resource Group if it doesn't exist
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $ResourceGroup)
    {
        $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    }

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIpAddressName `
        -AllocationMethod Dynamic -DomainNameLabel $DNSLabelPrefix -Sku Basic -IpAddressVersion IPv4 -IdleTimeoutInMinutes 4 

    if ($SharedResources -eq 'New')
    {
        # Create Network Security Group with allow RDP Rule
        $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name RDP -Priority 300 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
            -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
        $NetworkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

        # Create Virtual Network with default subnet
        $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix
        $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet
    }
    else 
    {
        # Select existing NSG if it is already exists
        $NetworkSecurityGroup = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $NetworkSecurityGroupName

        # Select existing VNet if it is already exists
        $VirtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VirtualNetworkName
    }

    $SubnetId = $VirtualNetwork.Subnets.Where( { $_.Name -eq $SubnetName }).id

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $SubnetId 
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkInterfaceName `
        -NetworkSecurityGroupId $NetworkSecurityGroup.Id -IpConfiguration $NetworkInterfaceIPConfig 
    
    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType $OSDiskType
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName 'MicrosoftVisualStudio' -Offer 'visualstudio2019latest' -Skus 'vs-2019-comm-latest-ws2019' -Version latest
    
    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential -EnableAutoUpdate -ProvisionVMAgent

    # Create Virtual Machine
    $DeployStatus = (New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig).IsSuccessStatusCode
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution is failed with the following error, and manual clean up is required." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $DeployStatus = $false
}
finally
{
    # Display the deployment status
    if ($DeployStatus) 
    { 
        [PSCustomObject]@{
            AdminUsername            = $AdminCredential.UserName
            VirtualNetworkName       = $VirtualNetworkName
            NetworkSecurityGroupName = $NetworkSecurityGroupName
            Hostname                 = $PublicIpAddress.DnsSettings.Fqdn
        }
        Write-Host -ForegroundColor Green "Deployment is successful!" 
    }
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}