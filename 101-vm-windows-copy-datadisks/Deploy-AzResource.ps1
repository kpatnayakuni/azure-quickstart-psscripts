[CmdletBinding()]
param
(
    # Resource Group Name
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location, 

    # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [Parameter(Mandatory = $true)]
    [string] $DNSLabelPrefix,

    # The Windows version for the VM.
    [Parameter(Mandatory = $false)]
    [ValidateSet('2016-Datacenter', '2016-Datacenter-Server-Core', '2016-Datacenter-Server-Core-smalldisk', 
        '2016-Datacenter-smalldisk', '2016-Datacenter-with-Containers', '2016-Nano-Server')]
    [string] $OSVersion = '2016-Datacenter',
    
    # The number of dataDisks to be returned in the output array.
    [Parameter(Mandatory = $false)]
    [int] $NumberOfDataDisks = 16,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential
)

# Declare local variables
$ImagePublisher = 'MicrosoftWindowsServer'
$ImageOffer = 'WindowsServer'
$NicName = 'myVMNic'
$AddressPrefix = '10.0.0.0/16'
$SubnetName = 'Subnet'
$SubnetPrefix = '10.0.0.0/24'
$PublicIPAddressName = 'myPublicIP'
$PublicIPAddressType = 'Dynamic'
$VMName = 'VMDataDisks'
$VMSize = 'Standard_DS4_v2'
$VirtualNetworkName = 'MyVNET'
$NetworkSecurityGroupName = 'default-NSG'

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
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIpAddressName `
        -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSLabelPrefix

    # Create Network Security Group with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $VirtualNetwork.Subnets[0].Id
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NicName -IpConfiguration $NetworkInterfaceIPConfig

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $OSVersion -Version latest
    
    # Add Data Disk(s)
    1..$NumberOfDataDisks | ForEach-Object { 
        $DiskName = "{0}{1}" -f $VMName.ToLower(), $_
        $Lun = $_ - 1
        $null = $VMConfig | Add-AzVMDataDisk -Name $DiskName -DiskSizeInGB 1023 -Lun $Lun -CreateOption Empty 
    }   

    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

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
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!" 
        Write-Host -ForegroundColor Green $PublicIpAddress.DnsSettings.Fqdn
    }
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
