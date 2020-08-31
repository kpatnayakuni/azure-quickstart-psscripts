[CmdletBinding()]
param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [parameter(Mandatory = $true)]
    [string] $Location, 

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # Unique DNS Name for the Public IP used to access the Virtual Machine.
    [parameter(Mandatory = $false)]
    [string] $DNSLabelPrefix = ('vm-', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join '',

    # The Windows version for the VM. This will pick a fully patched image of this given Windows version.
    [parameter(Mandatory = $false)]
    [ValidateSet("2016-Datacenter",
        "2016-Datacenter-Server-Core",
        "2016-Datacenter-Server-Core-smalldisk",
        "2016-Datacenter-smalldisk",
        "2016-Datacenter-with-Containers",
        "2016-Datacenter-with-RDSH",
        "2016-Datacenter-zhcn",
        "2019-Datacenter",
        "2019-Datacenter-Core",
        "2019-Datacenter-Core-smalldisk",
        "2019-Datacenter-Core-with-Containers",
        "2019-Datacenter-Core-with-Containers-smalldisk",
        "2019-datacenter-gensecond",
        "2019-Datacenter-smalldisk",
        "2019-Datacenter-with-Containers",
        "2019-Datacenter-with-Containers-smalldisk",
        "2019-Datacenter-zhcn",
        "Datacenter-Core-1803-with-Containers-smalldisk",
        "Datacenter-Core-1809-with-Containers-smalldisk",
        "Datacenter-Core-1903-with-Containers-smalldisk")]
    [string] $WindowsOSVersion = '2019-Datacenter',

    # Department Tag
    [parameter(Mandatory = $false)]
    [string] $DepartmentName = 'MyDepartment',

    # Application Tag
    [parameter(Mandatory = $false)]
    [string] $ApplicationName = 'MyApp',

    # Created By Tag 
    [parameter(Mandatory = $false)]
    [string] $CreatedBy = 'MyName',

    # Size for the virtual machine
    [parameter(Mandatory = $false)]
    [string] $VMSize = 'Standard_D2_V3'
)

# Declare local variables
$StorageAccountName = ('satagsvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''
$ImagePublisher = "MicrosoftWindowsServer"
$ImageOffer = "WindowsServer"
$NICName = "myVMNic"
$AddressPrefix = "10.0.0.0/16"
$SubnetName = "Subnet"
$SubnetPrefix = "10.0.0.0/24"
$StorageAccountType = "Standard_LRS"
$PublicIPAddressName = "myPublicIP"
$PublicIPAddressType = "Dynamic"
$VMName = "MyVM"
$VirtualNetworkName = "MyVNET"
$NetworkSecurityGroupName = "default-NSG"

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

    # Create tags
    $Tags = @{
        Department   = $DepartmentName
        Application  = $ApplicationName
        "Created By" = $CreatedBy
    }

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName $StorageAccountType -Kind Storage -Tag $Tags

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSLabelPrefix -Tag $Tags
   
    # Create Network Security Group with allow RDP Rule
    $NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig -Name 'default-allow-3389' -Priority 1000 -Access Allow -Direction Inbound -DestinationPortRange 3389 `
        -Protocol Tcp -SourcePortRange * -SourceAddressPrefix * -DestinationAddressPrefix *
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet -Tag $Tags

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $VirtualNetwork.Subnets[0].Id
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICName -IpConfiguration $NetworkInterfaceIPConfig -Tag $Tags

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize -Tags $Tags
    
    # Operating System configuration
    $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $WindowsOSVersion -Version latest

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