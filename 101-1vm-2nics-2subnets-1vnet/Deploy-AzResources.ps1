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
    [parameter(Mandatory = $false)]
    [ValidateSet('Standard_LRS', 'Premium_LRS')]
    [string] $StorageAccountType = 'Standard_LRS', # Storage Account type for the VM and VM diagnostic storage.
    [parameter(Mandatory = $false)]
    [string] $VMSize = 'Standard_DS1_v2'  # Size of the virtual machine, virtual machine size (has to be at least the size of Standard_A3 to support 2 NICs)
)

# Declaring local variables
$VMName = "VM-MultiNic"     # Virtual Machine Name
$Nic1 = "nic-1"     # Network Interface Card 1 Name
$Nic2 = "nic-2"     # Network Interface Card 2 Name
$VirtualNetworkName = "VirtualNetwork"          # Virtual Network Name
$AddressPrefix = "10.0.0.0/16"     # Virtual Network Address Space
$Subnet1Name = "Subnet-1"          # Subnet 1 Name
$Subnet1Prefix = "10.0.0.0/24"     # Subnet 1 Address Prefix
$Subnet2Name = "Subnet-2"          # Subnet 2 Name
$Subnet2Prefix = "10.0.1.0/24"     # Subnet 2 Address Prefix
$PublicIPAddressName = "publicIP"      # Public IP Address Name
$StorageAccountName = ('diags', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 16 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$NetworkSecurityGroupName1 = "NSG"     # Network Security Group 1 Name for Primary NIC
$NetworkSecurityGroupName2 = "$Subnet2Name-NSG"     # Network Security Group 2 Name for 2nd NIC

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

    # Create Network Security Group 1 with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup1 = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName1 -SecurityRules $NetwrokSecurityRule

    # Create Network Security Group 2 
    $NetworkSecurotyGroup2 = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName2

    # Create Virtual Network with 2 subnets
    $Subnet1 = New-AzVirtualNetworkSubnetConfig -Name $Subnet1Name -AddressPrefix $Subnet1Prefix 
    $Subnet2 = New-AzVirtualNetworkSubnetConfig -Name $Subnet2Name -AddressPrefix $Subnet2Prefix -NetworkSecurityGroupId $NetworkSecurotyGroup2.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $virtualNetworkName -AddressPrefix $addressPrefix -Subnet $Subnet1, $Subnet2

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod Dynamic
    
    # Create Network Interface Card 1
    $NetworkInterfaceCard1 = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $Nic1 -SubnetId $VirtualNetwork.Subnets[0].Id `
        -PublicIpAddressId $publicIpAddress.Id -NetworkSecurityGroupId $NetworkSecurotyGroup1.Id
    
    # Create Network Interface Card 2
    $NetworkInterfaceCard2 = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $Nic2 -SubnetId $VirtualNetwork.Subnets[1].Id

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName $StorageAccountType -Kind Storage

    ### Create Virtual Mchine
    ## VM Configuration
    # Virtual Machine Credentials
    $AdminCredential = [pscredential]::new($AdminUsername, $AdminPassword)

    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $adminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter' -Version latest

    # Add NIC 1
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard1.Id -Primary 
    
    # Add NIC 2
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard2.Id
    
    # Enable Boot Diagnostics
    $null = $VMConfig | Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -Enable -StorageAccountName $StorageAccountName

    # Create Virtual Machine
    $DeployStatus = (New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig).IsSuccessStatusCode
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
    { 
        Write-Host -ForegroundColor Green "Deployment is successful!"
        Write-Host ("HostName: {0}" -f $PublicIpAddress.IpAddress)
    }
    else 
    { 
        Write-Host -ForegroundColor Red "Deployment is unsuccessful!" 
    }
}
