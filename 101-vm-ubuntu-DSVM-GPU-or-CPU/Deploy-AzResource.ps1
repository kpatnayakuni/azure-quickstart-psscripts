[CmdletBinding()]
param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [parameter(Mandatory = $true)]
    [string] $Location, 

    # Username for the Virtual Machine.
    [parameter(Mandatory = $true)]
    [string] $AdminUsername, 

    # The name of you Virtual Machine.
    [parameter(Mandatory = $true)]
    [string] $VMName,

    # Choose between CPU or GPU processing
    [parameter(Mandatory = $false)]
    [ValidateSet('CPU-4GB', 'CPU-7GB', 'CPU-8GB', 'CPU-14GB', 'CPU-16GB', 'GPU-56GB')]
    [string] $CPUorGPU = 'CPU-4GB',

    # Name fo the VNET
    [Parameter(Mandatory = $false)]
    [string] $VirtualNetworkName = 'vNet',

    # Name of the subnet in the virtual network
    [Parameter(Mandatory = $false)]
    [string] $SubnetName = 'subnet',

    # Name of the Network Security Group
    [Parameter(Mandatory = $false)]
    [string] $NetworkSecurityGroupName = 'SecGroupNet',

    # Type of authentication to use on the Virtual Machine. SSH key is recommended.
    [parameter(Mandatory = $false)]
    [ValidateSet('sshPublicKey', 'password')]
    [string] $AuthenticationType = 'sshPublicKey', 

    # Password for the Virtual Machine. SSH key is recommended.
    [parameter(Mandatory = $true)]
    [securestring] $AdminPassword 
)

# Declare local variables
$NetworkInterfaceName = "{0}-NetInt" -f $VMName
$PublicIpAddressName = "{0}-PublicIP" -f $VMName
$OSDiskType = "Standard_LRS"
$StorageAccountName = ('salinuxvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$StorageAccountType = "Standard_LRS"
$StorageAccountKind = "Storage"
$VMSize = @{
    "CPU-4GB"  = "Standard_B2s"
    "CPU-7GB"  = "Standard_DS2_v2"
    "CPU-8GB"  = "Standard_D2s_v3"
    "CPU-14GB" = "Standard_DS3_v2"
    "CPU-16GB" = "Standard_D4s_v3"
    "GPU-56GB" = "Standard_NC6_Promo"
}

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
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName -AllocationMethod Dynamic -Sku Basic

    # Create Network Security Group with allow JupyterHub, RStudioServer, SSH Rule
    $JupyterHubNSRule = New-AzNetworkSecurityRuleConfig -Name 'JupyterHub' -Priority 1010 -Protocol Tcp -Access Allow -Direction Inbound `
        -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8000
    $RStudioServerNSRule = New-AzNetworkSecurityRuleConfig -Name 'RStudioServer' -Priority 1020 -Protocol Tcp -Access Allow -Direction Inbound `
        -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8787
    $SSHNSRule = New-AzNetworkSecurityRuleConfig -Name 'SSH' -Priority 1030 -Protocol Tcp -Access Allow -Direction Inbound `
        -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
    $NetworkSecurotyGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkSecurityGroupName -SecurityRules $JupyterHubNSRule, $RStudioServerNSRule, $SSHNSRule

    # Create Virtual Network with default subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix '10.0.0.0/24' -PrivateEndpointNetworkPoliciesFlag Enabled -PrivateLinkServiceNetworkPoliciesFlag Enabled
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix '10.0.0.0/16' -Subnet $Subnet

    # Create Network Interface Card
    $IPConfiguration = New-AzNetworkInterfaceIpConfig -Name 'ipconfig1' -SubnetId $VirtualNetwork.Subnets[0].Id -PublicIpAddressId $PublicIpAddress.Id 
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NetworkInterfaceName -IpConfiguration $IPConfiguration -NetworkSecurityGroupId $NetworkSecurotyGroup.Id

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName $StorageAccountType -Kind $StorageAccountKind

    ### Create Virtual Mchine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName "$VMName-$CPUorGPU" -VMSize $VMSize[$CPUorGPU]

    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType $OSDiskType
    $null = $VMConfig | Set-AzVMSourceImage -PublisherName "microsoft-dsvm" -Offer "ubuntu-1804" -Skus "1804-gen2" -Version latest

    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary
    
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
        Write-Host -ForegroundColor Green "AdminUsername: $AdminUsername"
        Write-Host -ForegroundColor Green "Deployment is successful!" 
    }
    else { Write-Host -ForegroundColor Red "Deployment is unsuccessful!" }
}

<#
D:\'OneDrive - kpatnayakuni.com'\Projects\GitRepos\azure-quickstart-psscripts\101-vm-ubuntu-DSVM-GPU-or-CPU\Deploy-AzResource.ps1 -ResourceGroupName dsvm-rg -Location westus -AdminUsername sysadmin -VMName dsvm

cmdlet Deploy-AzResource.ps1 at command pipeline position 1
Supply values for the following parameters:
AdminPassword: *************

AdminUsername: sysadmin
Deployment is successful!
#>