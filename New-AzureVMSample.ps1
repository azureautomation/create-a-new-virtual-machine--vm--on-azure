<#
.SYNOPSIS 
    Creates a new Virtual Machine (VM) on Azure

.DESCRIPTION
    This runbook creates a new Virtual Machine (VM) on Azure.
    The Connect-Azure runbook needs to be imported and published before this runbook can be sucessfully run.
    
    The runbook waits untill VM boots
    
.PARAMETER AzureConnectionName
    Name of the Azure connection asset that was created in the Automation service.
    This connection asset contains the subscription id and the name of the certificate asset that 
    holds the management certificate for this subscription.
    
.PARAMETER ServiceName
    Name of the cloud service which VM will belong to. A new cloud service will be created if cloud service by name ServiceName does not exists

.PARAMETER VMName    
    Name of the virtual machine. 

.PARAMETER VMCredentialName
   Name of the credential asset ( that has username/password) used for VM login
   
.PARAMETER VMSize
   Specifies the size of the instance. Supported values are as below with their (cores, memory) 
   "ExtraSmall" (shared core, 768 MB),
   "Small"      (1 core, 1.75 GB),
   "Medium"     (2 cores, 3.5 GB),
   "Large"      (4 cores, 7 GB),
   "ExtraLarge" (8 cores, 14GB),
   "A5"         (2 cores, 14GB)
   "A6"         (4 cores, 28GB)
   "A7"         (8 cores, 56 GB)
  
.PARAMETER OSName
    Name of the OS that need to be used for the VM 
    OSName can be found here:
    New -> Compute -> Virtual Machine -> From Gallery -> 'Choose an Image' page -> Pick OSName from the list
   
    Alternatively, get OS name by executing Azure activity
    Get-AzureVMImage
    (Look for 'Label' property for OS name)

.PARAMETER Location
    Location of the datacenter where VM will be created. One of the below
    Supported values for Location: "West US", "East US", "North US", "South US", "West Europe", "North Europe", "East Asia", 'Southeast Asia'
    If an existing Cloud Service is provided using ServiceName parameter, Location parameter won't be used
    
.PARAMETER StorageAccountName
   Name of storage account used for the subscription. If storage does not exists, new storage account will be created.
  Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only.
  
.EXAMPLE
 1) Create Certificate Asset "myCert":
    Use the certificate file (.pfx or .cer file) to create a Certificate asset for ex. "myCred" in 
    Azure -> Automation -> select automation account "MyAutomationAccount" -> Assets -> Add Setting -> Add Credential -> 
    Certificate -> Provide name "myCred" and upload the certificate file (.pfx or .cer)
    
    The same certificate must be associated with the subscription, You can verify the same for your subscription 
    at Azure -> Settings -> Management Certificates
2) Create Azure Connection Asset "AzureConnection"
    Azure -> Automation -> select automation account "MyAutomationAccount" -> Assets -> Add Setting 
    -> Add Connection -> Select 'Azure' from dropdown -> Provide name ex. "AzureConnection"  ->
    Provide AutomationCertificateName "myCert" you created in step 1 and subscription Id
    
3) To run runbook: Test or Start the runbook from Author tab
  
  to call from another runbook, ex:
  New-AzureVMSample -AzureConnectionName "AzureConnection" -ServiceName "myService" -VMName "myVM" -VMCredentialName "myVMCred" -OSName "Windows Server 2012 R2 Datacenter" -Location "East US" -VMSize "Large" -StorageAccountName "mystgacc"  

.NOTES
    AUTHOR: Viv Lingaiah
    LASTEDIT: Apr 15 , 2014 
#>
workflow New-AzureVMSample
{
    Param
    (
        [parameter(Mandatory=$true)] [String] $AzureConnectionName,
	    [parameter(Mandatory=$true)] [String] $ServiceName,
        [parameter(Mandatory=$true)] [String] $VMName,
        [parameter(Mandatory=$true)] [String] $VMCredentialName,
	    [parameter(Mandatory=$true)] [String] $OSName,
        [parameter(Mandatory=$true)] [String] $Location,
        [parameter(Mandatory=$true)] [String] $StorageAccountName,
        [parameter(Mandatory=$false)] [String] $VMSize = "ExtraSmall"  
    )
     
    # Call the Connect-Azure Runbook to set up the connection to Azure using the Automation connection asset
    Connect-Azure -AzureConnectionName $AzureConnectionName 
    
    $VMCred = Get-AutomationPSCredential -Name $VMCredentialName
    if($VMCred -eq $null)
    {
        throw "No Credential asset was found by name {0}. Please create it." -f  $Using:VMCredentialName
    } 
    
    $VMUserName = $VMCred.UserName
    $VMPassword = $VMCred.GetNetworkCredential().Password
   
    InlineScript
    {
        # Select the Azure subscription we will be working against
        Select-AzureSubscription -SubscriptionName $Using:AzureConnectionName
        $sub = Get-AzureSubscription -SubscriptionName $Using:AzureConnectionName
            
        # Check whether a VM by name $VMName already exists, if does not exists create VM
         Write-Output ("Checking whether VM '{0}' already exists.." -f $Using:VMName)
        $AzureVM = Get-AzureVM -ServiceName $Using:ServiceName -Name $Using:VMName
        if ($AzureVM -eq $null)
        {
            Write-Output ("VM '{0}' does not exist. Will create it." -f $Using:VMName)
            
            Write-Output ("Getting the VM Image list for OS '{0}'.." -f $Using:OSName)
            # get OS Image list for $OSName
            $OSImages=Get-AzureVMImage | Where-Object {($_.Label -ne $null) -and ($_.Label.Contains($Using:OSName))}
            if ($OSImages -eq $null) 
       	    {
          	 throw "'Get-AzureVMImage' activity: Could not get OS Images whose label contains OSName '{0}'" -f $Using:OSName
            } 
            Write-Output ("Got the VM Image list for OS '{0}'.." -f $Using:OSName)
            
            # Get the latest VM Image info for OSName provided
            $OSImages = $OSImages | Sort-Object -Descending -Property PublishedDate 
            $OSImage = $OSImages |  Select-Object -First 1 
                                  
            if ($OSImage -eq $null) 
       	    {
          	 throw " Could not get an OS Image whose label contains OSName '{0}'" -f $Using:OSName
            } 
            Write-Output ("The latest VM Image for OS '{0}' is '{1}'. Will use it for VM creation" -f $Using:OSName, $Using:OSImage.ImageName)
            $stgAcc = Get-AzureStorageAccount -StorageAccountName $Using:StorageAccountName
            
            if( $stgAcc -eq $null)
            {
                Write-Output "Creating Storage Account"
                $result = New-AzureStorageAccount -StorageAccountName $Using:StorageAccountName -Location $Using:Location
                
                if ($result -eq $null)
                {
                   throw "Azure Storage Account '{0}' was not created successfully" -f $Using:StorageAccountName
                } 
                else
                {
                   Write-Output ("Storage account '{0}' was created successfully" -f $Using:StorageAccountName)
                }
            }
            else
            {
                 Write-Output ("Storage account '{0}' already exists. Will use it for VM creation" -f $Using:StorageAccountName)
            }        
            Set-AzureSubscription -SubscriptionName $Using:AzureConnectionName -CurrentStorageAccountName $Using:StorageAccountName
            
            #check cloud service by name $ServiceName already exists
            $CloudServiceInfo = Get-AzureService -ServiceName $Using:ServiceName
            
            Write-Output ("Creating VM with service name  {0}, VM name {1}, image name {2}, Location {3}" -f $Using:ServiceName, $Using:VMName, $OSImage.ImageName, $Location)
             
            # Create VM    
            if( $OSImage.OS -eq "Linux" )
            {
               if( $CloudServiceInfo -eq $null)
               {
                   $AzureVMConfig = New-AzureQuickVM -Linux -ServiceName $Using:ServiceName -Name $Using:VMName -ImageName $OSImage.ImageName -Password $Using:VMPassword -LinuxUser $Using:VMUserName -Location $Using:Location -InstanceSize $Using:VMSize -WaitForBoot 
               }
               else
               {
                    $AzureVMConfig = New-AzureQuickVM -Linux -ServiceName $Using:ServiceName -Name $Using:VMName -ImageName $OSImage.ImageName -Password $Using:VMPassword -LinuxUser $Using:VMUserName -InstanceSize $Using:VMSize -WaitForBoot 
               }
            }
            if( $OSImage.OS -eq "Windows" )
            {
               if( $CloudServiceInfo -eq $null)
               {
                    $AzureVMConfig = New-AzureQuickVM -Windows -ServiceName $Using:ServiceName -Name $Using:VMName -ImageName $OSImage.ImageName -Password $Using:VMPassword -AdminUserName $Using:VMUserName -Location $Using:Location -InstanceSize $Using:VMSize -WaitForBoot
               }
               else
               {
                   $AzureVMConfig = New-AzureQuickVM -Windows -ServiceName $Using:ServiceName -Name $Using:VMName -ImageName $OSImage.ImageName -Password $Using:VMPassword -AdminUserName $Using:VMUserName -InstanceSize $Using:VMSize -WaitForBoot
               } 
            }
    
            $AzureVM = Get-AzureVM -ServiceName $Using:ServiceName -Name $Using:VMName
            if ( ($AzureVM -ne $null) ) 
       	    {
          	    Write-Output ("VM '{0}' with OS '{1}' was created successfully" -f $Using:VMName, $Using:OSName)
            }
            else
            {
                throw "Could not retrieve info for VM '{0}'. VM was not created" -f $Using:VMName
            } 
        }
        else
        {
            Write-Output ("VM '{0}' already exists. Not creating it again" -f $Using:VMName)
        }      
    } 
}