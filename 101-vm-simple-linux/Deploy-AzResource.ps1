[CmdletBinding()]
param
(
    [parameter(Mandatory)]
    [string] $ResourceGroupName, # Resource Group Name

    [parameter(Mandatory)]
    [string] $Location, # Location for all resources.

    [parameter(Mandatory)]
    [string] $AdminUsername, # Username for the Virtual Machine.

    [parameter(Mandatory = $false)]
    [ValidateSet('sshPublicKey', 'password')]
    [string] $AuthenticationType = 'sshPublicKey', # Type of authentication to use on the Virtual Machine. SSH key is recommended.

    [parameter(Mandatory, HelpMessage = "Enter admin password or leave ot blank for SSH Key")]
    [securestring] $AdminPassword, # password for the Virtual Machine. SSH key is recommended.

    [parameter(Mandatory = $false)]
    [string] $KeyFileName, # SSH Key file

    [parameter(Mandatory)]
    [string]$DNSLabelPrefix, # Unique DNS Name for the Public IP used to access the Virtual Machine.

    [parameter(Mandatory = $false)]
    [ValidateSet('12.04.5-LTS', '14.04.5-LTS', '16.04.0-LTS', '18.04-LTS')]
    [string]$UbuntuOSVersion = '16.04.0-LTS'  # The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version.
)


$StorageAccountName = ('salinuxvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$ImagePublisher = "Canonical"
$ImageOffer = "UbuntuServer"
$NICName = "myVMNic"         # Network Interface Card Name
$AddressPrefix = "10.0.0.0/16"     # Virtual Network Address Space
$SubnetName = "Subnet"          # Subnet Name
$SubnetPrefix = "10.0.0.0/24"     # Subnet Address Prefix
$StorageAccountType = "Standard_LRS"
$PublicIPAddressName = "myPublicIP"      # Public IP Address Name
$PublicIPAddressType = "Dynamic"
$VMName = "LinuxVM"     # Virtual Machine Name
$VMSize = "Standard_A1"
$VirtualNetworkName = "MyVNET"          # Virtual Network Name
$NetworkSecurityGroupName = "default-NSG"     # Network Security Group Name

# Break the script if the resource group is already exists
if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) 
{
    Write-Error -Message "Cannot continue with this deployment since the '$ResourceGroupName' resource group is already exists."
    return
}

# Supress the warning messages and stop the script on error
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

try
{
    # Create Resource Group
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName $StorageAccountType -Kind Storage

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSLabelPrefix

    # Create Network Security Group with allow SSH Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-22' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 22 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Network Interface Card
    $IPConfiguration = New-AzNetworkInterfaceIpConfig -Name 'ipconfig1' -SubnetId $VirtualNetwork.Subnets[0].Id -PublicIpAddressId $PublicIpAddress.Id 
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICName -IpConfiguration $IPConfiguration

    ### Create Virtual Mchine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Virtual Machine Credentials & Operating System configuration
    $AdminCredential = [pscredential]::new($AdminUsername, $AdminPassword)
    if ($AuthenticationType -eq 'password')
    {
        $null = $VMConfig | Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $AdminCredential
    }
    elseif ($AuthenticationType -eq 'sshPublicKey')
    {
        $null = $VMConfig | Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $AdminCredential -DisablePasswordAuthentication
        $KeyData = Get-Content -Path $KeyFileName
        $null = Add-AzVMSshPublicKey -VM $VMConfig -KeyData $KeyData -Path "/home/$AdminUsername/.ssh/authorized_keys"
    }

    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $UbuntuOSVersion -Version latest

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
    
    Write-Host "Execution is failed with the following error, and cleaning up the deployment..." -ForegroundColor Red
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
        Write-Host ("SSH Command: ssh {0}@{1}" -f $AdminUsername, $PublicIpAddress.DnsSettings.Fqdn)
    }
    else 
    { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
