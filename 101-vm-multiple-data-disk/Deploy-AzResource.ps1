[CmdLetBinding()]
Param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location,
    
    # Size of VM
    [Parameter(Mandatory = $True)]
    [string] $VMSize,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # Unique DNS Name for the Storage Account where the Virtual Machine's disks will be placed.
    [Parameter(Mandatory = $True)]
    [string] $DNSLabelPrefix,

    # Size of each data disk in GB
    [Parameter(Mandatory = $True)]
    [string] $SizeOfEachDataDiskInGB
)

# Declare local variables
$StorageAccountName = ('saddiskvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''
$StorageAccountType = 'Standard_LRS'
$PublicIPAddressName = 'myPublicIP'
$PublicipAddressType = 'Dynamic'
$VirtualNetworkName = 'myVNET'
$AddressPrefix = '10.0.0.0/16'
$Subnet1Name = 'Subnet-1'
$Subnet1Prefix = '10.0.0.0/24'
$NICName = 'myNIC'
$VMName = 'myVM'
$ImagePublisher = 'MicrosoftWindowsServer'
$ImageOffer = 'WindowsServer'
$ImageSku = '2012-Datacenter'
$ImageVersion = 'latest'
$NetworkSecurityGroupName = 'default-NSG'

# Supress the warning messages and stop the script on error
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

# Break the script is the resource group is already exists
if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) 
{
    Write-Error -Message "Cannot continue with this deployment since the '$ResourceGroupName' resource group is already exists."
    return
}

try
{
    # Create Resource Group
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null

    # Commonly used parameters
    $DefaultSplat = @{
        ResourceGroupName = $ResourceGroupName 
        Location          = $Location
    }

    # Create Storage Account
    New-AzStorageAccount @DefaultSplat -Name $StorageAccountName -SkuName $StorageAccountType | Out-Null

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress @DefaultSplat -Name $PublicIPAddressName -AllocationMethod $PublicipAddressType -DomainNameLabel $DNSLabelPrefix
   
    # Create Network Security Group with allow RDP Rule
    $SRRule = @{
        Name                     = 'default-allow-3389'
        Priority                 = 1000 
        Access                   = 'Allow' 
        Direction                = 'Inbound' 
        DestinationPortRange     = 3389 
        Protocol                 = 'Tcp' 
        SourcePortRange          = '*' 
        SourceAddressPrefix      = '*' 
        DestinationAddressPrefix = '*'
    }
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig @SRRule
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup @DefaultSplat -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $Subnet1Name -AddressPrefix $Subnet1Prefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork @DefaultSplat -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $VirtualNetwork.Subnets[0].Id
    $NetworkInterfaceCard = New-AzNetworkInterface @DefaultSplat -Name $NicName -IpConfiguration $NetworkInterfaceIPConfig    

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential | Out-Null
    
    # VM Source Image Referance
    $VMConfig | Set-AzVMOSDisk -CreateOption FromImage | Out-Null
    $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSku -Version $ImageVersion | Out-Null
    
    # Add Data Disks
    0..3 | ForEach-Object { 
        $DiskSplat = @{
            Name         = $("{0}-DataDisk-{1}" -f $VMName, ($_ + 1)) 
            DiskSizeInGB = $SizeOfEachDataDiskInGB 
            Lun          = $_ 
            CreateOption = 'Empty'
        }
        $VMConfig | Add-AzVMDataDisk  @DiskSplat | Out-Null
    }

    # Add NIC
    $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary | Out-Null

    # Enable Boot Diagnostics
    $VMConfig | Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -Enable -StorageAccountName $StorageAccountName | Out-Null

    # Create Virtual Machine
    $DeployStatus = (New-AzVM @DefaultSplat -VM $VMConfig).IsSuccessStatusCode
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution is failed with the following error, and cleaning the deployment..." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $DeployStatus = $false
    Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
}
finally
{
    # Display the deployment status
    if ($DeployStatus) 
    { Write-Host -ForegroundColor Green "Deployment is successful!" }
    else 
    { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
