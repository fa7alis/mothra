<#
.SYNOPSIS
	Installs Symantec DLP Software in a networked Windows environment
.DESCRIPTION
	This script will install Symantec DLP Software in a configured production environment
.EXAMPLE
	PS> ./mothra
.NOTES
	Author: Shawn Cook
    InteliStaging Authors: Michael Tiebout, Daniel Stuetz
.LINK
	https://github.com/fa7alis/mothra
#>

param (
    [string]$Logfile  = "C:\Mothra.log"
)

### Checking for Mothra.log ###
Test-Path -path $Logfile
if ($Logfile){
Remove-Item $Logfile -erroraction SilentlyContinue
}

$DataStamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

### LogWrite Function ###
Function LogWrite
{
   Param ([string]$logstring)
   Write-Host "$DataStamp $logstring"
   Add-content $Logfile -value "$DataStamp $logstring"
}

### Loading data from and formatting CSV file ###
$computers = New-Object System.Collections.ArrayList
ForEach($line in (Get-Content "C:\DetectionServerList.csv")){
    if($line -match "^(?!HOST)[A-Za-z\d]+") {
        $trimmed = $line.trim()
        $computers.Add($trimmed) > $null
    }

}


### Start Main Script ###
Clear-Host
Write-Host " __    __     ______     ______   __  __     ______     ______" -ForegroundColor Green
Write-Host "/\ `"-./  \   /\  __ \   /\__  _\ /\ \_\ \   /\  == \   /\  __ \" -ForegroundColor Green
Write-Host "\ \ \-./\ \  \ \ \/\ \  \/_/\ \/ \ \  __ \  \ \  __<   \ \  __ \" -ForegroundColor Green
Write-Host " \ \_\ \ \_\  \ \_____\    \ \_\  \ \_\ \_\  \ \_\ \_\  \ \_\ \_\" -ForegroundColor Green
Write-Host "  \/_/  \/_/   \/_____/     \/_/   \/_/\/_/   \/_/ /_/   \/_/\/_/" -ForegroundColor Green
Write-Host "-----------------------------------------------------------------" -ForegroundColor Green
Write-Host "PS Script to install SymantecDLP in a networked Windows Environment"
Write-Host "-----------------------------------------------------------------" -ForegroundColor Green
Write-Host "For SymantecDLP installation we assume FIPS being disabled, and Existing Service User." -ForegroundColor Red -BackgroundColor Yellow
Write-Host "If this is not the case then manually install SymantecDLP." -ForegroundColor Red -BackgroundColor Yellow
Read-Host -Prompt "Press Enter to continue" -ForegroundColor Red -BackgroundColor Yellow

### Prompt for installation variables ###
Write-Host "Input the SymantecDLP Install Directory:" -ForegroundColor Green
$installDir = Read-Host
Write-Host "Input the SymantecDLP JRE Directory to use:" -ForegroundColor Green
$javaDir = Read-Host
Write-Host "Input the SymantecDLP Data Directory to use:" -ForegroundColor Green
$dataDir = Read-Host
Write-Host "Input the existing Service User name to use:" -ForegroundColor Green
$svcUsername = Read-Host
Write-Host "Input the existing Service User password to use:" -ForegroundColor Green
$svcPassword = Read-host -AsSecureString
$svcPW = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($svcPassword))


### Open dialog box to select appropriate MSI/MSP installer ###
Write-Host "We will now open a File Browser. Select the MSI file to be installed." -ForegroundColor Green
Read-Host -prompt "Press Enter to continue"

Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    Multiselect = $false # Cannot select multiple files
	Filter = 'MSI (*.MSI, *.MSP)|*.msi;*.msp' # Specified file types
    }
[void]$FileBrowser.ShowDialog()
$installer = Get-ChildItem $FileBrowser.FileName

### Log installation values for troubleshooting ###
LogWrite "Using $installDir as SymantecDLP Install directory"
LogWrite "Using $javaDir as SymantecDLP JRE directory"
LogWrite "Using $dataDir as SymantecDLP Data directory"
LogWrite "Using $svcUsername as SymantecDLP Service Username"
LogWrite "Using $installer as Install source file"

### Installing Symantec DLP MSI from staging folder ###
$installLog = '{0}-{1}.log' -f $installer.Name,$DataStamp
$MSIArguments = @(
    "/i"
    ('"{0}"' -f $installer.Name)
    "/qn"
    "/norestart"
    "INSTALLATION_DIRECTORY=$installDir"
    "DATA_DIRECTORY=$dataDir"
    "JRE_DIRECTORY=$javaDir"
    "FIPS_OPTION=Disabled"
    "SERVICE_USER_OPTION=ExistingUser"
    "SERVICE_USER_USERNAME=$svcUsername"
    "SERVICE_USER_PASSWORD=$svcPW"
    "/L*v"
    $installLog
    )

$i = 0
foreach ($computer in $computers) {
    Invoke-Command -ComputerName $computer -ScriptBlock { 
        Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow 
    }   
    $i++
    Write-Progress -activity "Installing DLP on Detection Servers..." -status "Tested: $i of $($computers.Count)" -percentComplete (($i / $computers.Count)  * 100)
}