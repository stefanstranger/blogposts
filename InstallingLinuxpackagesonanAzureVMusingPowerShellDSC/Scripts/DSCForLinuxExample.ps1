# ---------------------------------------------------
# Script: C:\\DSCForLinuxExample.ps1
# Version: 0.1
# Author: Stefan Stranger
# Date: 01/13/2017 19:58:43
# Description: Script with all the code used in the blog post Installing Linux packages on an Azure VM using PowerShell DSC
# Comments:
# Changes:  
# Disclaimer: 
# This example is provided “AS IS” with no warranty expressed or implied. Run at your own risk. 
# **Always test in your lab first**  Do this at your own risk!! 
# The author will not be held responsible for any damage you incur when making these changes!
# ---------------------------------------------------

#region variables
$VMName = '[enter VM Name]'
$ResourceGroupName = '[Enter Resource Group name]'
$ExtensionName = 'DSCForLinux'
$Location = '[Enter Azure Location]'
$StorageAccountname = '[Enter Storage Account Name]' #Lowercase!!
$DSCForLinuxFile = 'c:\temp\localhost.mof' #enter location where you compiled the mof file
#endregion

#region 1. Connect to Azure
Add-AzureRmAccount
 
#Select Azure Subscription
$subscription = 
    (Get-AzureRmSubscription |
        Out-GridView `
        -Title 'Select an Azure Subscription ...' `
    -PassThru)
 
Set-AzureRmContext -SubscriptionId $subscription.subscriptionId -TenantId $subscription.TenantID
#endregion

#region 2. create storage account if not created yet
New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountName -Type Standard_LRS -Location $Location
Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountName -OutVariable storageaccount
#endregion 

#region 3. Create a container. The permission is set to Off which means the container is only accessible to the owner.
Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountName
New-AzureStorageContainer -Name dscforlinux -Permission Off #lowercase!!
#endregion

#region 4. Create initial DSC Configuration
Configuration ExampleConfiguration{

    Import-DscResource -Module nx

    Node  "localhost"{
    nxFile ExampleFile {

        DestinationPath = "/tmp/example"
        Contents = "hello world `n"
        Ensure = "Present"
        Type = "File"
    }

    }
}

ExampleConfiguration -OutputPath: "C:\temp"
#endregion

#region 5. Add your template to the container.
Set-AzureStorageBlobContent -Container dscforlinux -File $DSCForLinuxFile
#endregion 

#region 6. Create a SAS token with read permissions and an expiry time to limit access. Retrieve the full URI of the template including the SAS token.
$templateuri = New-AzureStorageBlobSASToken -Container dscforlinux -Blob 'localhost.mof' -Permission r -ExpiryTime (Get-Date).AddMonths(6) -FullUri
#endregion 

#region 7. list storage keys
Invoke-AzureRmResourceAction -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Storage/storageAccounts -ResourceName $StorageAccountname -Action listKeys -ApiVersion 2015-05-01-preview -Force -OutVariable keys
#endregion

#region 8. deploy DSC for linux extension

#Check extension
$extensionName = 'DSCForLinux'
$publisher = 'Microsoft.OSTCExtensions'
Get-AzureRmVMExtensionImage -PublisherName Microsoft.OSTCExtensions -Location $location -Type DSCForLinux #Check lastes version
$version = '2.0'

# You need to change the values in the private config according to your own settings. 
#StorageAccountKey can be retrieved from region 7.
#run $keys[0].key1 and paste info into StorageAccountKey property. 
$privateConfig = '{
  "StorageAccountName": "[Enter storage account name]",
  "StorageAccountKey": "[Enter Storage Account key]"
}'

#FileUri inf can be retrieved from $templateUri variable
$publicConfig = '{
  "Mode": "Push",
  "FileUri": "[Enter FileUri ($TemplateUri output value)]"
}'

Set-AzureRmVMExtension -ResourceGroupName $ResourceGroupName -VMName $vmName -Location $location `
  -Name $extensionName -Publisher $publisher -ExtensionType $extensionName `
  -TypeHandlerVersion $version -SettingString $publicConfig -ProtectedSettingString $privateConfig
#endregion

#region retrieve dsc logs remotely via ssh
$credential = Get-Credential
$sshsession = New-SSHSession -ComputerName 'stsdscforlinuxvm01.westeurope.cloudapp.azure.com' -Credential $credential
Invoke-SSHCommand -Command {uname -a} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region Get DSC Config
Invoke-SSHCommand -Command {sudo /opt/microsoft/dsc/Scripts/GetDscConfiguration.py} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region Check DSC version
Invoke-SSHCommand -Command {sudo dpkg -l | grep dsc} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region check DSC Mof files
Invoke-SSHCommand -Command {sudo ls /opt/microsoft/dsc/mof} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region update to latest OMI Package version
#Download the latest omi package from Github and save in /tmp folder
Invoke-SSHCommand -Command {sudo wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.deb -P /tmp} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region update to latest DSC version
#Download the latest DSC from Github and save in /tmp folder
Invoke-SSHCommand -Command {sudo wget wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.deb -P /tmp} -SSHSession $sshsession | select -ExpandProperty output
#endregion


#region install OMI and DSC
#Download the latest DSC from Github and save in /tmp folder
Invoke-SSHCommand -Command {sudo dpkg -i /tmp/omi-1.1.0.ssl_100.x64.deb /tmp/dsc-1.1.1-294.ssl_100.x64.deb} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region check DSC nxPackage Resource info
Invoke-SSHCommand -Command {sudo cat /opt/microsoft/dsc/modules/nx/DSCResources/MSFT_nxPackageResource/MSFT_nxPackageResource.schema.mof} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region list Linux DSC Scripts
Invoke-SSHCommand -Command {sudo ls /opt/microsoft/dsc/Scripts} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region Step 10. Create new DSC Config with nxPackage DSC resource
configuration demopackage {
    Import-DscResource -ModuleName nx

    node "localhost" {
        nxPackage cowsay {
            Name = 'cowsay'
            Ensure = 'Present'
            PackageManager = 'Apt'
            PackageGroup = $false
        }
    }
}

demopackage -OutputPath: "C:\temp\Cowsay"
#endregion

#region 11. Upload DSC Config file using Set-SFTPFile
$SFTPSession = New-SFTPSession -ComputerName '[enter fqdn of Azure Ubuntu VM]' -Credential $credential
Set-SFTPFile -SFTPSession $SFTPSession -LocalFile 'C:\temp\cowsay\localhost.mof' -RemotePath /tmp

#region Start DSC Config
Invoke-SSHCommand -Command {sudo /opt/microsoft/dsc/Scripts/StartDscConfiguration.py -configurationmof /tmp/localhost.mof} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#region Run Cowsay
Invoke-SSHCommand -Command {cowsay "Hello World!"} -SSHSession $sshsession | select -ExpandProperty output
#endregion

#endregion