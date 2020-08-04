[CmdletBinding()]
param
(
    # Resource Group Name
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName, 

    # Location for all resources.
    [Parameter(Mandatory = $true)]
    [string] $Location, 

    # Administrator credential
    [Parameter(Mandatory = $true)]
    [pscredential] $AdminCredential,

    # Prefix to use for VM names
    [Parameter(Mandatory = $false)]
    [string] $VMNamePrefix = 'BackendVM'
)

# Declaring local variables
$AvailabilitySetName = 'AvSet'
$StorageAccountType = 'Standard_LRS'
$StorageAccountName = ('sawinvm', -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 8 | ForEach-Object { [char]$_ })) -join ''    # Generate unique storage account name
$VirtualNetworkName = 'vNet'
$SubnetName = 'backendSubnet'
$LoadBalancerName = 'ilb'
$NetworkInterfaceName = 'nic'
$NumberOfInstances = 2

# Supress the warning messages
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

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

    # Create Storage Account
    $null = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Location $Location -Name $StorageAccountName -SkuName $StorageAccountType -Kind Storage

    # Create Availability Set
    $AvailabilitySet = New-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -Location $Location -Name $AvailabilitySetName -Sku Aligned -PlatformUpdateDomainCount 2 -PlatformFaultDomainCount 2

    # Create Virtual Network with subnet
    $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.2.0/24" 
    $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location -Name $VirtualNetworkName -AddressPrefix "10.0.0.0/16" -Subnet $Subnet

    # Create Internal LoadBalancer
    $LBFrontendIPConfig = New-AzLoadBalancerFrontendIpConfig -Name LoadBalancerFrontend -SubnetId $VirtualNetwork.Subnets[0].Id -PrivateIpAddress "10.0.2.6" 
    $LBBackendAddressPool = New-AzLoadBalancerBackendAddressPoolConfig -Name BackendPool1
    $LBProbe = New-AzLoadBalancerProbeConfig -Protocol Tcp -Name lbprobe -Port 80 -IntervalInSeconds 15 -ProbeCount 2
    $LBRule = New-AzLoadBalancerRuleConfig -Name lbrule -Protocol Tcp -FrontendPort 80 -BackendPort 80 -IdleTimeoutInMinutes 15 -FrontendIpConfigurationId $LBFrontendIPConfig.Id -BackendAddressPoolId $LBBackendAddressPool.Id -ProbeId $LBProbe.Id
    $null = New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LoadBalancerName -Location $Location -Sku Standard -FrontendIpConfiguration $LBFrontendIPConfig -BackendAddressPool $LBBackendAddressPool -Probe $LBProbe -LoadBalancingRule $LBRule

    # Create Network Interface Card with internal load balancer
    $NICConfig = New-AzNetworkInterfaceIpConfig -Name ipconfig1 -SubnetId $VirtualNetwork.Subnets[0].Id -LoadBalancerBackendAddressPoolId $LBBackendAddressPool.Id
    $NetworkInterfaceCard = 1..$NumberOfInstances | ForEach-Object {
        $NICName = $NetworkInterfaceName + $_
        New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICName -IpConfiguration $NICConfig
    }

    ### Create Virtual Machine
    ## VM Configuration
    1..$NumberOfInstances | ForEach-Object {    

        # VMName and Computer Name
        $VMName = $VMNamePrefix + $_

        # New Virtual Machine Configuration with availability set
        $VMConfig = New-AzVMConfig -VMName $VMName -VMSize Standard_DS2_V2 -AvailabilitySetId $AvailabilitySet.Id
    
        # Operating System configuration
        $null = $VMConfig | Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $AdminCredential
    
        # VM Source Image Referance
        $null = $VMConfig | Set-AzVMOSDisk -CreateOption FromImage
        $null = $VMConfig | Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus 2016-Datacenter -Version latest

        # Add NIC
        $null = $VMConfig | Add-AzVMNetworkInterface -Id $NetworkInterfaceCard[$($_ - 1)].Id -Primary

        # Enable Boot Diagnostics
        $null = $VMConfig | Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -Enable -StorageAccountName $StorageAccountName

        # Create Virtual Machine
        New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig
    }

    # Deployment status
    $DeployStatus = $true
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
    }
    else 
    { 
        Write-Host -ForegroundColor Red "Deployment is unsuccessful!" 
    }
}