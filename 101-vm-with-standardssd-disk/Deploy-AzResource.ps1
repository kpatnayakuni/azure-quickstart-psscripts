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
    [parameter(Mandatory = $true)]
    [string] $VirtualMachineName,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # The Storage type of the data Disks
    [Parameter(Mandatory = $false)]
    [ValidateSet('StandardSSD_LRS', 'Standard_LRS', 'Premium_LRS')]
    [string] $DiskType = 'StandardSSD_LRS',

    # The virtual machine size. Enter a Premium capable VM size if DiskType is entered as Premium_LRS
    [Parameter(Mandatory = $false)]
    [string] $VirtualMachineSize = 'Standard_DS3_V2',

    # The Windows version for the VM.
    [Parameter(Mandatory = $false)]
    [ValidateSet('2008-R2-SP1', '2012-Datacenter', '2012-R2-Datacenter', '2016-Datacenter')]
    [string] $WindowsOSVersion = '2016-Datacenter'
)

# Declare local variables
$DataDiskSize = 1024
$DataDisksCount = 5
$ImagePublisher = "MicrosoftWindowsServer"
$ImageOffer = "WindowsServer"
$AddressPrefix = "10.2.3.0/24"
$SubnetPrefix = "10.2.3.0/24"
$PublicIPAddressType = "Dynamic"
$VirtualNetworkName = "{0}-vnet" -f $VirtualMachineName.ToLower()
$SubnetName = "{0}-subnet" -f $VirtualMachineName.ToLower()
$OSDiskName = "{0}OSDisk" -f $VirtualMachineName.ToLower()
$NetworkInterfaceName = "{0}-nic" -f $VirtualMachineName.ToLower() 
$PublicIpAddressName = "{0}-ip" -f $VirtualMachineName.ToLower() 
$NetworkSecurityGroupName = "{0}-nsg" -f $VirtualMachineName.ToLower() 

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
        -AllocationMethod $PublicIPAddressType -Sku Basic -IpAddressVersion IPv4

    # Create Network Security Group with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $VirtualNetwork.Subnets[0].Id
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkInterfaceName -IpConfiguration $NetworkInterfaceIPConfig

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VirtualMachineName -VMSize $VirtualMachineSize
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VirtualMachineName -Credential $AdminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage -Name $OSDiskName -Caching ReadWrite -StorageAccountType $DiskType -DiskSizeInGB 128 
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $WindowsOSVersion -Version latest
    
    # Add Data Disk(s)
    1..$DataDisksCount | ForEach-Object {
        $DiskName = "{0}DataDisk{1}" -f $VirtualMachineName.ToLower(), $_
        $Lun = $_ - 1
        $null = $VMConfig | Add-AzVMDataDisk -Name $DiskName -DiskSizeInGB $DataDiskSize -Lun $Lun -CreateOption Empty -StorageAccountType $DiskType
    }   

    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

    # If the VM is created using premium storage or managed disk then it will create a new standard storage account for boot diagnostics by default
    # Disable the boot diagnostics
    $null = $VMConfig | Set-AzVMBootDiagnostic -Disable

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
    { Write-Host -ForegroundColor Green "Deployment is successful!" }
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
