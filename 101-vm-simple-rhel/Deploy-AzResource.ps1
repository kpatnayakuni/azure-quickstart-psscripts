[CmdLetBinding()]
Param
(
	# Resource Group Name
	[Parameter(Mandatory = $True)]
	[string] $ResourceGroupName,

	# Location for all resources.
	[Parameter(Mandatory = $True)]
	[string] $Location,

	# Name for the Virtual Machine.
	[Parameter(Mandatory = $True)]
	[string] $VMName,

	# User name for the Virtual Machine.
	[Parameter(Mandatory = $True)]
	[string] $AdminUsername,

	# Type of authentication to use on the Virtual Machine. SSH key is recommended.
	[Parameter(Mandatory = $False)]
	[ValidateSet('sshPublicKey', 'password')]
	[string] $Authenticationtype = 'sshPublicKey',

	# Password for the Virtual Machine. SSH key is recommended.
	[Parameter(Mandatory = $False)]
	[securestring] $AdminPassword = $(' ' | ConvertTo-SecureString -AsPlainText -Force),
	
	# SSH Key 
	[Parameter(Mandatory = $False)]
	[string] $KeyFileName
)

# Declare local variables
$DataDisk1Name = '{0}-datadisk1' -f $VMName
$DataDisk2Name = '{0}-datadisk2' -f $VMName
$ImagePublisher = 'RedHat'
$ImageOffer = 'RHEL'
$ImageSKU = '7.2'
$Nicname = '{0}-nic' -f $VMName
$Addressprefix = '10.0.0.0/16'
$Subnetname = 'Subnet'
$Subnetprefix = '10.0.0.0/24'
$PublicIPAddressName = '{0}publicip' -f $VMName
$PublicIPAddressType = 'Dynamic'
$Vmsize = 'Standard_A2'
$Virtualnetworkname = '{0}-vnet' -f $VMName
$Networksecuritygroupname = 'default-NSG'

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

	# Commonly used parameters
	$DefaultSplat = @{
		ResourceGroupName = $ResourceGroupName 
		Location          = $Location
	}

	# Create Public IP Address
	$PublicIpAddress = New-AzPublicIpAddress @DefaultSplat -Name $PublicIPAddressName -AllocationMethod $PublicIPAddressType

	# Create Network Security Group with allow SSH Rule
	$SRSplat = @{
		Name                     = 'default-allow-22' 
		Priority                 = 1000 
		Access                   = 'Allow' 
		Direction                = 'Inbound' 
		DestinationPortRange     = 22
		Protocol                 = 'Tcp' 
		SourcePortRange          = '*' 
		SourceAddressPrefix      = '*' 
		DestinationAddressPrefix = '*'
	}
	$NetwrokSecurityRule = New-AzNetworkSecurityRuleConfig @SRSplat
	$NetworkSecurotyGroup = New-AzNetworkSecurityGroup @DefaultSplat -Name $NetworkSecurityGroupName -SecurityRules $NetwrokSecurityRule

	# Create Virtual Network with default subnet
	$Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroupId $NetworkSecurotyGroup.Id
	$VirtualNetwork = New-AzVirtualNetwork @DefaultSplat -Name $VirtualNetworkName -AddressPrefix $AddressPrefix -Subnet $Subnet

	# Create Network Interface Card
	$IPConfiguration = New-AzNetworkInterfaceIpConfig -Name 'ipconfig1' -SubnetId $VirtualNetwork.Subnets[0].Id -PublicIpAddressId $PublicIpAddress.Id 
	$NetworkInterfaceCard = New-AzNetworkInterface @DefaultSplat -Name $NICName -IpConfiguration $IPConfiguration

	### Create Virtual Mchine
	## VM Configuration
	# New Virtual Machine Configuration
	$VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize -Tags @{Tag1 = 'ManagedVM' }
    
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
	$null = $VMConfig | Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSKU -Version latest
 
	# Add Data Disks
	$null = $VMConfig | Add-AzVMDataDisk -Name $DataDisk1Name -DiskSizeInGB 100 -Lun 0 -CreateOption Empty
	$null = $VMConfig | Add-AzVMDataDisk -Name $DataDisk2Name -DiskSizeInGB 100 -Lun 1 -CreateOption Empty
	
	# Add NIC
	$null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

	# Create Virtual Machine
	$DeployStatus = (New-AzVM @DefaultSplat -VM $VMConfig).IsSuccessStatusCode
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
 	{ Write-Host -ForegroundColor Green "Deployment is successful!" }
	else 
 	{ Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}
