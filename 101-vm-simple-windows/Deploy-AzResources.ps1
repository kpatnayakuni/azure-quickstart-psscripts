[CmdletBinding()]
param
(
    [parameter(Mandatory)]
    [string] $resourceGroupName, # Resource Group Name
    [parameter(Mandatory)]
    [string] $location, # Location for all resources.
    [parameter(Mandatory)]
    [string] $adminUsername, # Username for the Virtual Machine.
    [parameter(Mandatory)]
    [securestring] $adminPassword, # Password for the Virtual Machine.
    [parameter(Mandatory)]
    [string] $dnsLabelPrefix, # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [parameter(Mandatory = $false)]
    [ValidateSet('2008-R2-SP1', '2012-Datacenter', '2012-R2-Datacenter', '2016-Nano-Server', '2016-Datacenter-with-Containers', '2016-Datacenter', '2019-Datacenter')]
    [string] $windowsOSVersion = '2016-Datacenter', # The Windows version for the VM. This will pick a fully patched image of this given Windows version.
    [parameter(Mandatory = $false)]
    [string] $vmSize = 'Standard_A2_v2'  # Size of the virtual machine.
)

# Declaring local variables
$storageAccountName = ('sawinvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$nicName = "myVMNic"         # Network Interface Card Name
$addressPrefix = "10.0.0.0/16"     # Virtual Network Address Space
$subnetName = "Subnet"          # Subnet Name
$subnetPrefix = "10.0.0.0/24"     # Subnet Address Prefix
$publicIPAddressName = "myPublicIP"      # Public IP Address Name
$vmName = "SimpleWinVM"     # Virtual Machine Name
$virtualNetworkName = "MyVNET"          # Virtual Network Name
$networkSecurityGroupName = "default-NSG"     # Network Security Group Name

# Supress the warning messages
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

# Break the script is the resource group is already exists
if (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue) 
{
    Write-Error -Message "Cannot continue with this deployment since the '$resourceGroupName' resource group is already exists."
    return
}

try
{
    # Create Resource Group
    $null = New-AzResourceGroup -Name $resourceGroupName -Location $location

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $resourceGroupName -Location $location -Name $storageAccountName -SkuName Standard_LRS -Kind Storage

    # Create Network Security Group with allow RDP Rule
    $netwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $networkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $networkSecurityGroupName -SecurityRules $netwrokSecurityRule

    # Create Virtual Network with default subnet
    $subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPrefix -NetworkSecurityGroupId $networkSecurotyGroup.Id
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $virtualNetworkName -AddressPrefix $addressPrefix -Subnet $subnet

    # Create Public IP Address
    $publicIpAddress = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Location $location -Name $publicIPAddressName -AllocationMethod Dynamic -DomainNameLabel $dnsLabelPrefix
    
    # Create Network Interface Card
    $networkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $resourceGroupName -Location $location -Name $nicName -SubnetId $virtualNetwork.Subnets[0].Id -PublicIpAddressId $publicIpAddress.Id 

    ### Create Virtual Mchine
    ## VM Configuration
    # Virtual Machine Credentials
    $adminCredential = [pscredential]::new($adminUsername, $adminPassword)

    # New Virtual Machine Configuration
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    
    # Operating System configuration
    $null = $vmConfig | Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $adminCredential
    
    # VM Source Image Referance
    $null = $vmConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $vmConfig | Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus $windowsOSVersion -Version latest

    # Add NIC
    $null = $vmConfig | Add-AzVMNetworkInterface -Id $networkInterfaceCard.Id -Primary
    
    # Add Data Disk
    $null = $vmConfig | Add-AzVMDataDisk -DiskSizeInGB 1023 -Lun 0 -CreateOption Empty

    # Enable Boot Diagnostics
    $null = $vmConfig | Set-AzVMBootDiagnostic -ResourceGroupName $resourceGroupName -Enable -StorageAccountName $storageAccountName

    # Create Virtual Machine
    $DeployStatus = (New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig).IsSuccessStatusCode
}
catch
{
    # For any reason if the deployment is failed, then rolling it back
    Write-Host "Execution failed, cleaning the deployment..." -ForegroundColor Red
    $DeployStatus = $false
    $null = Remove-AzResourceGroup -Name $resourceGroupName -Force 
}
finally
{
    # Display the deployment status
    if ($DeployStatus) 
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!"
        Write-Host ("HostName: {0}" -f $publicIpAddress.DnsSettings.Fqdn)
    }
    else 
    { 
        Write-Host -ForegroundColor Red "Deployment is unsuccessful!" 
    }
}
