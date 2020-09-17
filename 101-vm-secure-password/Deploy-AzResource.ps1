[CmdLetBinding()]
Param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [parameter(Mandatory = $true)]
    [string] $Location, 
    
    # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [Parameter(Mandatory = $False)]
    [string] $DNSLabelPrefix = ('vm-', -join ((48..57) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join '',

    # The Windows version for the VM. This will pick a fully patched image of this given Windows version. Allowed values: 2008-R2-SP1, 2012-Datacenter, 2012-R2-Datacenter.
    [Parameter(Mandatory = $False)]
    [ValidateSet('2012-Datacenter', '2012-R2-Datacenter', '2016-Datacenter', '2019-Datacenter')]
    [string] $WindowsOSVersion = '2019-Datacenter',

    # Size of the VM
    [Parameter(Mandatory = $False)]
    [string] $VMSize = 'Standard_D2_v3',

    # KeyVault name to fetch the password of the given user name
    [Parameter(Mandatory = $true)]
    [string] $KeyVaultName,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [string] $AdminUserName
)

# Declare local variables
$StorageAccountName = ('sawinvm', -join ((48..57) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''
$StorageAccountType = 'Standard_LRS'
$ImagePublisher = 'MicrosoftWindowsServer'
$ImageOffer = 'WindowsServer'
$PublicIPAddressName = 'myPublicIP'
$PublicIPAddressType = 'Dynamic'
$VirtualNetworkName = 'MyVNET'
$AddressPrefix = '10.0.0.0/16'
$SubnetName = 'Subnet'
$SubnetPrefix = '10.0.0.0/24'
$NetworkSecurityGroupName = "{0}-nsg" -f $SubnetName
$NICName = 'myVMNic'
$VMName = 'SimpleWindowsVM'

# Supress the warning messages and stop the script on error
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

try
{
    # Create Resource Group if it doesn't exist
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $ResourceGroup)
    {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    }

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
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork @DefaultSplat -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $VirtualNetwork.Subnets[0].Id
    $NetworkInterfaceCard = New-AzNetworkInterface @DefaultSplat -Name $NicName -IpConfiguration $NetworkInterfaceIPConfig  

    # Fetch password from Azure KetVault
    $KeyVault = Get-AzKeyVault -VaultName $KeyVaultName
    $Secret = Get-AzKeyVaultSecret -VaultName $KeyVault.VaultName -Name $AdminUserName | ForEach-Object SecretValue

    # Admin credential
    $AdminCredential = New-Object System.Management.Automation.PSCredential ($AdminUserName, $Secret)

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential | Out-Null
    
    # VM Source Image Referance
    $VMConfig | Set-AzVMOSDisk -CreateOption FromImage | Out-Null
    $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $WindowsOSVersion -Version latest | Out-Null
    
    # Add Data Disks
    $VMConfig | Add-AzVMDataDisk -DiskSizeInGB 1023 -Lun 0 -CreateOption Empty | Out-Null

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
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
