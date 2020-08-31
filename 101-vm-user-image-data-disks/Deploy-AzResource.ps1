[CmdletBinding(DefaultParameterSetName = 'New')]
param
(
    # Resource Group Name
    [parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [parameter(Mandatory = $true)]
    [string] $Location, 

    # This is the name of the your VM
    [parameter(Mandatory = $true)]
    [string] $VMName, 

    # This is the name of the your storage account
    [parameter(Mandatory = $true)]
    [string] $BootDiagnosticsStorageAccountName,

    # Resource group of the existing storage account
    [parameter(Mandatory = $true)]
    [string] $BootDiagnosticsStorageAccountResourceGroupName,

    # URI in Azure storage of the blob (VHD) that you want to use for the OS disk. 
    # eg. https://mystorageaccount.blob.core.windows.net/osimages/osimage.vhd
    [parameter(Mandatory = $true)]
    [string] $OSDiskVhdUri,

    # URI in Azure storage of the blob (VHD) that you want to use for the data disk. 
    # eg. https://mystorageaccount.blob.core.windows.net/dataimages/dataimage.vhd
    [parameter(Mandatory = $true)]
    [string] $DataDiskVhdUri,

    # Disk Storage Type
    [parameter(Mandatory = $false)]
    [ValidateSet('Standard_LRS', 'Premium_LRS')]
    [string] $DiskStorageType = 'Premium_LRS',

    # DNS Label for the Public IP. Must be lowercase. 
    # It should match with the following regular expression: ^[a-z][a-z0-9-]{1,61}[a-z0-9]$ or it will raise an error.
    [parameter(Mandatory = $true)]
    [string] $DNSLabelPrefix,

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # This is the OS that your VM will be running
    [Parameter(Mandatory = $true)]
    [ValidateSet('Windows', 'Linux')]
    [string] $OSType,

    # This is the size of your VM
    [Parameter(Mandatory = $true)]
    [string] $VMSize,

    # New VNet Name
    [Parameter(Mandatory = $true, ParameterSetName = 'New')]
    [string] $NewVNetName,

    # New Subnet Name
    [Parameter(Mandatory = $true, ParameterSetName = 'New')]
    [string] $NewSubnetName,

    # Existing VNet Name
    [Parameter(Mandatory = $true, ParameterSetName = 'Existing')]
    [string] $ExistingVNetName,

    # Existing Subnet Name
    [Parameter(Mandatory = $true, ParameterSetName = 'Existing')]
    [string] $ExistingSubnetName,

    # Existing VNet Resource Group Name
    [Parameter(Mandatory = $true, ParameterSetName = 'Existing')]
    [string] $ExistingVnetResourceGroupName
)

# Declare local variables
$ImageName = "myCustomImage"
$PublicIPAddressName = "{0}-IP" -f $VMName
$PublicIPAddressType = "Dynamic"
$NicName = "{0}-NIC" -f $VMName

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

    # Create image from the user disks in a storage account
    $ImageConfig = New-AzImageConfig -Location $Location
    $null = Set-AzImageOsDisk -Image $ImageConfig -OsType $OSType -OsState 'Generalized' -BlobUri $OSDiskVhdUri
    $null = Add-AzImageDataDisk -Image $ImageConfig -Lun 1 -BlobUri $DataDiskVhdUri -StorageAccountType Standard_LRS
    $Image = New-AzImage -Image $ImageConfig -ImageName $ImageName -ResourceGroupName $ResourceGroupName

    # Use an existing Virtual Network or Create Virtual Network with default subnet
    if ($PSCmdlet.ParameterSetName -eq 'Existing')
    {
        $VirtualNetwork = Get-AzVirtualNetwork -Name $ExistingVNetName -ResourceGroupName $ExistingVnetResourceGroupName
        $Subnetid = $VirtualNetwork.Subnets.Where( { $_.Name -eq $ExistingSubnetName }).id
    }
    else
    {    
        $Subnet = New-AzVirtualNetworkSubnetConfig -Name $NewSubnetName -AddressPrefix '10.0.0.0/24'
        $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $NewVNetName -AddressPrefix '10.0.0.0/16' -Subnet $Subnet
        $Subnetid = $VirtualNetwork.Subnets[0].id
    }

    # Create Public IP Address
    $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPAddressName `
        -AllocationMethod $PublicIPAddressType -DomainNameLabel $DNSLabelPrefix

    # Create Network Interface Card
    $NetworkInterfaceIPConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIpAddressId $PublicIpAddress.Id -SubnetId $Subnetid
    $NetworkInterfaceCard = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NicName -IpConfiguration $NetworkInterfaceIPConfig

    # Get an existing storage account or create a new storage account for boot diagnostics
    if ($null -eq $(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue))
    {
        $null = New-AzResourceGroup -Name $BootDiagnosticsStorageAccountResourceGroupName -Location $Location
    }
    if ($null -eq $(Get-AzStorageAccount -ResourceGroupName $BootDiagnosticsStorageAccountResourceGroupName -Name $BootDiagnosticsStorageAccountName -ErrorAction SilentlyContinue))
    {
        $null = New-AzStorageAccount -ResourceGroupName $BootDiagnosticsStorageAccountResourceGroupName -Location $Location -Name $BootDiagnosticsStorageAccountName -SkuName Standard_LRS
    }

    ### Create Virtual Machine
    ## VM Configuration
    # New Virtual Machine Configuration
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    
    # Operating System configuration
    switch ($OSType)
    {
        'Windows' { $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential }
        'Linux' { $null = $VMConfig | Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $AdminCredential }
    }
    
    # VM Source Image Referance
    $null = $VMConfig | Set-AzVMSourceImage -Id $Image.Id    

    # Add NIC
    $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard.Id -Primary

    # Enable the boot diagnostics
    $null = $VMConfig | Set-AzVMBootDiagnostic -Enable -ResourceGroupName $BootDiagnosticsStorageAccountResourceGroupName -StorageAccountName $BootDiagnosticsStorageAccountName

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