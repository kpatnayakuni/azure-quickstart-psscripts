[CmdletBinding()]
param
(
    [parameter(Mandatory)]
    [string] $ResourceGroupName, # Resource Group Name

    [parameter(Mandatory)]
    [string] $Location, # Location for all resources.

    [parameter(Mandatory)]
    [string] $AdminUsername, # Username for the Virtual Machine.

    [parameter(Mandatory)]
    [securestring] $AdminPassword, # Password for the Virtual Machine.

    [parameter(Mandatory)]
    [string] $DNSLabelPrefix, # Unique DNS Name for the Public IP used to access the Virtual Machine.

    [parameter(Mandatory = $false)]
    [ValidateSet('2008-R2-SP1', '2012-Datacenter', '2012-R2-Datacenter', '2016-Nano-Server', '2016-Datacenter-with-Containers', '2016-Datacenter', '2019-Datacenter')]
    [string] $WindowsOSVersion = '2016-Datacenter', # The Windows version for the VM. This will pick a fully patched image of this given Windows version.
    
    [parameter(Mandatory = $false)]
    [string] $VMSize = 'Standard_A2_v2'  # Size of the virtual machine.
)

# Declaring local variables
$StorageAccountName = ('sawinvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$NICName = "myVMNic"         # Network Interface Card Name
$AddressPrefix = "10.0.0.0/16"     # Virtual Network Address Space
$SubnetName = "Subnet"          # Subnet Name
$SubnetPrefix = "10.0.0.0/24"     # Subnet Address Prefix
$PublicIPAddressName = "myPublicIP"      # Public IP Address Name
$VMName = "SimpleWinVM"     # Virtual Machine Name
$VirtualNetworkName = "MyVNET"          # Virtual Network Name
$NetworkSecurityGroupName = "default-NSG"     # Network Security Group Name

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
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName Standard_LRS -Kind Storage

    # Create Network Security Group with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod Dynamic -DomainNameLabel $DNSLabelPrefix
    
    # Create Network Interface Card
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICName -SubnetId $VirtualNetwork.Subnets[0].Id -PublicIpAddressId $PublicIpAddress.Id 

    ### Create Virtual Machine
    ## VM Configuration
    # Virtual Machine Credentials
    $AdminCredential = [pscredential]::new($AdminUsername, $AdminPassword)

    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus $WindowsOSVersion -Version latest

    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary
    
    # Add Data Disk
    $null = $VMConfig | Add-AzVMDataDisk -DiskSizeInGB 1023 -Lun 0 -CreateOption Empty

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
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!"
        Write-Host ("HostName: {0}" -f $PublicIpAddress.DnsSettings.Fqdn)
    }
    else 
    { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
