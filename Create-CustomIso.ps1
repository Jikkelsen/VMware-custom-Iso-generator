
<#
   _____                _               _____          _                  _____           
  / ____|              | |             / ____|        | |                |_   _|          
 | |     _ __ ___  __ _| |_ ___ ______| |    _   _ ___| |_ ___  _ __ ___   | |  ___  ___  
 | |    | '__/ _ \/ _` | __/ _ \______| |   | | | / __| __/ _ \| '_ ` _ \  | | / __|/ _ \ 
 | |____| | |  __/ (_| | ||  __/      | |___| |_| \__ \ || (_) | | | | | |_| |_\__ \ (_) |
  \_____|_|  \___|\__,_|\__\___|       \_____\__,_|___/\__\___/|_| |_| |_|_____|___/\___/ 
                                                                                          
#>

# Make sure Python is installed. This is needed for the .iso generation
$PythonInstall = python --version 2>&1

# Python is not installed
if ($PythonInstall -is [System.Management.Automation.ErrorRecord])
{
    Write-Host "Python is not installed. Attempting install"
    Winget install python3.7 --accept-package-agreements

    
    Write-Host "Installing dependencies"
    $HOME\AppData\Local\Programs\Python\Python37\python.exe -m pip install -U pip
    pip install six psutil lxml pyopenssl

    Write-Host "OK"
}
else
{
    Write-Host "Python install validated; version $PythonInstall"
}

# Make sure scripts  can be run yes
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Check if the VMware.PowerCLI module is imported
if ($null -eq (Get-InstalledModule | Where-Object Name -match Vmware.PowerCLI))
{
  Install-Module -Name VMware.PowerCLI -SkipPublisherCheck -confirm:$false
}

# Don't make PowerCLI make noise
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false

# Set the path to the Python 3.7 executable (this specific version is required per VMware PowerCLI Compatibility Matrixes)
# You may have to manually change the python.exe path, but this is the path that chocolately installs it to by default
#Set-PowerCLIConfiguration -PythonPath "c:\python37\python.exe" -Scope User
#Set-PowerCLIConfiguration -PythonPath "C:\Program Files\WindowsApps\PythonSoftwareFoundation.Python.3.11_3.11.2544.0_x64__qbz5n2kfra8p0\python.exe" -Scope User

Set-PowerCLIConfiguration -PythonPath "C:\Users\Mikke\AppData\Local\Programs\Python\Python37\python.exe" -Scope User


#----------------------------------------------| Depots |----------------------------------------------#

$Filename = "ESXi-8.0U2-22380479-standard"
#region REMOVE ME

# Fetch ESXi image depot
Write-Host "Adding online depot ... " -NoNewline
$OnlineDepot = "https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml"
[void]::(Add-EsxSoftwareDepot $OnlineDepot)
Write-Host "OK"

# Check images that can be downloaded
#Get-EsxImageProfile

# Download desired image
$Params = @{
    ImageProfile   = $Filename
    filepath       = "$Filename.zip"
    ExportToBundle = $true
    Force          = $true
}   
Write-Host "Exporting $Filename to local zip file ... " -NoNewline
[void](Export-ESXImageProfile @Params)
Write-Host "OK"

Write-Host "Removing online depot again ... " -NoNewline
[void]::(Remove-EsxSoftwareDepot $OnlineDepot)
Write-host "OK"
#endregion

Write-Host "Importing local file as software depot"
[void]::(Add-EsxSoftwareDepot ".\$FileName.zip")
Write-HOst "OK"

#-----------------------------------------| Additional drivers |-----------------------------------------#

# Get community network driver
#$URI = "https://archive.org/download/flings.vmware.com/Flings/Community%20Networking%20Driver%20for%20ESXi/Net-Community-Driver_1.2.7.0-1vmw.700.1.0.15843807_19480755.zip"
#Invoke-WebRequest -Uri $URI -OutFile ".\Drivers\Net-Community-Driver_1.2.7.0-1vmw.700.1.0.15843807_1948075.zip"


Write-host "Adding drivers to depot"
foreach ($Driver in (Get-Item .\Drivers\*.zip))
{
    try 
    {
        Write-Host "`t$Driver... " -NoNewline
        [void]::(Add-EsxSoftwareDepot $Driver)
        Write-Host "OK"
    }
    catch
    {
        Write-Host "FAIL!" -BackgroundColor Red
        Write-Host "`tCould not add $Driver to bundle"
        throw
    }
}
Write-Host "All drivers injected"


#---------------------------------------------| Create iso |---------------------------------------------#

Write-Host "Creating new image profile ... " -NoNewline
$Params = @{
    CloneProfile = "ESXi-8.0U2-22380479-standard"
    Name         = "ESXi-8.0U2-22380479-standard-Net-Drivers"
    Vendor       = "Nordea_custom"
    Description  = "Some Drivers and nordea custom"
}
[void]::(New-EsxImageProfile @Params)
Write-host "OK"


# Allows to read .zip archives
Add-Type -assembly "system.io.compression.filesystem"


Write-Host "Injecting drivers to image profile"
Foreach ($Driver in (Get-Item .\Drivers\*.zip))
{
    try 
    {
        $DriverRelativePath = ([io.compression.zipfile]::OpenRead($Driver).Entries | Where-Object FullName -match ".vib").FullName
        $DriverName         = ($DriverRelativePath -split "/")[1]
    
        Write-Host "`t$DriverName... " -NoNewline
        [void]::(Add-EsxSoftwarePackage -ImageProfile "ESXi-8.0U2-22380479-standard-Net-Drivers" -SoftwarePackage $DriverName)
        Write-Host "OK"
    }
    catch
    {
        Write-Host "FAIL!" 
        Write-Host "`tCould not add driver"
        throw
    }
}


#---------------------------------------------| Export iso |---------------------------------------------#

Write-Host "Creating final .iso file ... " -NoNewline
$Params = @{
    ImageProfile = "ESXi-8.0U2-22380479-standard-Net-Drivers" 
    filepath     = "ESXi-8.0U2-22380479-standard-Net-Drivers.iso"
    ExportToIso  = $true
    Force        = $true
}
[void]::(Export-ESXImageProfile @Params)
Write-Host "OK"
explorer .
