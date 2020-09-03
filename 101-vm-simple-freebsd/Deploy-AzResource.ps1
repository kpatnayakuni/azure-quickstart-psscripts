[CmdletBinding(DefaultParameterSetName = 'SSHKey')]
param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [parameter(Mandatory = $true)]
    [string] $Location, 

    # Username for the Virtual Machine.
    [parameter(Mandatory)]
    [string] $AdminUsername, 

    # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [parameter(Mandatory)]
    [string]$DNSLabelPrefix, 

    # The FreeBSD version for the VM. This will pick a fully patched image of this given FreeBSD version.
    [parameter(Mandatory = $false)]
    [ValidateSet("11.2", "11.1", "11.0", "10.3")]
    [string] $FreeBSDOSVersion = "11.2",

    [parameter(Mandatory = $false, ParameterSetName = 'SSHKey')]
    [string] $SSHKey, # SSH Key 

    # Password for the Virtual Machine. SSH key is recommended.
    [parameter(Mandatory = $true, ParameterSetName = 'Password')]
    [securestring] $AdminPassword
)

# Declare local variables
$StorageAccountName = ('safreebsdvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$ImagePublisher = "MicrosoftOSTC"
$ImageOffer = "FreeBSD"
$NICName = "myVMNic" 
$AddressPrefix = "10.0.0.0/16" 
$SubnetName = "Subnet"        
$SubnetPrefix = "10.0.0.0/24"  
$StorageAccountType = "Standard_LRS"
$PublicIPAddressName = "myPublicIP" 
$PublicIPAddressType = "Dynamic"
$VMName = "MyFreeBSDVM"     
$VMSize = "Standard_A1"
$VirtualNetworkName = "MyVNET"  
$NetworkSecurityGroupName = "$SubnetName-NSG" 

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
    if ($PSCmdlet.ParameterSetName -eq 'Password')
    {
        $AdminCredential = [pscredential]::new($AdminUsername, $AdminPassword)    
        $null = $VMConfig | Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $AdminCredential
    }
    else
    {
        $AdminCredential = [pscredential]::new($AdminUsername, $(' ' | ConvertTo-SecureString -AsPlainText -Force))    
        $null = $VMConfig | Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $AdminCredential -DisablePasswordAuthentication
        $null = Add-AzVMSshPublicKey -VM $VMConfig -KeyData $SSHKey -Path "/home/$AdminUsername/.ssh/authorized_keys"
    }

    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $FreeBSDOSVersion -Version latest

    # Add Data Disk
    $null = $VMConfig | Add-AzVMDataDisk -DiskSizeInGB 1023 -Lun 0 -CreateOption Empty

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
        Write-Host ("HostName: {0}" -f $PublicIpAddress.DnsSettings.Fqdn)
        Write-Host ("SSH Command: ssh {0}@{1}" -f $AdminUsername, $PublicIpAddress.DnsSettings.Fqdn)
        Write-Host -ForegroundColor Green "Deployment is successful!"
    }
    else 
    { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
