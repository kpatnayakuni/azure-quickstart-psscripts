[CmdletBinding()]
param
(
    [parameter(Mandatory)]
    [string] $resourceGroupName, # Resource Group Name
    [parameter(Mandatory)]
    [string] $location, # Location for all resources.
    [parameter(Mandatory)]
    [string] $adminUsername, # Username for the Virtual Machine.
    [parameter(Mandatory = $false)]
    [ValidateSet('sshPublicKey', 'password')]
    [string] $authenticationType = 'sshPublicKey', # Type of authentication to use on the Virtual Machine. SSH key is recommended.
    [parameter(Mandatory, HelpMessage = "Enter admin password or leave ot blank for SSH Key")]
    [securestring] $adminPassword, # password for the Virtual Machine. SSH key is recommended.
    [parameter(Mandatory = $false)]
    [string] $KeyFileName, # SSH Key file
    [parameter(Mandatory)]
    [string]$dnsLabelPrefix, # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [parameter(Mandatory = $false)]
    [ValidateSet('12.04.5-LTS', '14.04.5-LTS', '16.04.0-LTS', '18.04-LTS')]
    [string]$ubuntuOSVersion = '16.04.0-LTS'  # The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version.
)

$storageAccountName = ('salinuxvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$imagePublisher = "Canonical"
$imageOffer = "UbuntuServer"
$nicName = "myVMNic"         # Network Interface Card Name
$addressPrefix = "10.0.0.0/16"     # Virtual Network Address Space
$subnetName = "Subnet"          # Subnet Name
$subnetPrefix = "10.0.0.0/24"     # Subnet Address Prefix
$storageAccountType = "Standard_LRS"
$publicIPAddressName = "myPublicIP"      # Public IP Address Name
$publicIPAddressType = "Dynamic"
$vmName = "SimpleWinVM"     # Virtual Machine Name
$vmSize = "Standard_A1"
$virtualNetworkName = "MyVNET"          # Virtual Network Name
$networkSecurityGroupName = "default-NSG"     # Network Security Group Name

# Break the script if the resource group is already exists
if (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue) 
{
    Write-Error -Message "Cannot continue with this deployment since the '$resourceGroupName' resource group is already exists."
    return
}

# Supress the warning messages
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

try
{
    # Create Resource Group
    $null = New-AzResourceGroup -Name $resourceGroupName -Location $location

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $resourceGroupName -Location $location -Name $storageAccountName -SkuName $storageAccountType -Kind Storage

    # Create Public IP Address
    $publicIpAddress = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Location $location -Name $publicIPAddressName -AllocationMethod $publicIPAddressType -DomainNameLabel $dnsLabelPrefix

    # Create Network Security Group with allow SSH Rule
    $netwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-2' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 22 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $networkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $networkSecurityGroupName -SecurityRules $netwrokSecurityRule

    # Create Virtual Network with default subnet
    $subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPrefix -NetworkSecurityGroupId $networkSecurotyGroup.Id
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $virtualNetworkName -AddressPrefix $addressPrefix -Subnet $subnet

    # Create Network Interface Card
    $ipConfiguration = New-AzNetworkInterfaceIpConfig -Name 'ipconfig1' -SubnetId $virtualNetwork.Subnets[0].Id -PublicIpAddressId $publicIpAddress.Id 
    $networkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $resourceGroupName -Location $location -Name $nicName -IpConfiguration $ipConfiguration

    ### Create Virtual Mchine
    ## VM Configuration
    # New Virtual Machine Configuration
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    
    # Virtual Machine Credentials & Operating System configuration
    $adminCredential = [pscredential]::new($adminUsername, $adminPassword)
    if ($authenticationType -eq 'password')
    {
        $null = $vmConfig | Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $adminCredential 
    }
    elseif ($authenticationType -eq 'sshPublicKey')
    {
        $null = $vmConfig | Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $adminCredential -DisablePasswordAuthentication
        $KeyData = Get-Content -Path $KeyFileName
        $null = Add-AzVMSshPublicKey -VM $vmConfig -KeyData $KeyData -Path "/home/$adminUsername/.ssh/authorized_keys"
    }

    # VM Source Image Referance
    $null = $vmConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $vmConfig | Set-AzVMSourceImage -PublisherName $imagePublisher -Offer $imageOffer -Skus $ubuntuOSVersion -Version latest

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
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Execution failed, cleaning up the deployment..." -ForegroundColor Red
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
        Write-Host ("SSH Command: ssh {0}@{1}" -f $adminUsername, $publicIpAddress.DnsSettings.Fqdn)
    }
    else 
    { 
        Write-Host -ForegroundColor Red "Deployment is unsuccessful!" 
    }
}
