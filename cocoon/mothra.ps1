<#
.SYNOPSIS
	Stages, installs, and updates Symantec DLP Software in a configured environment
.DESCRIPTION
	This script will stage, install, and update Symantec DLP Software in a configured production environment
.EXAMPLE
	PS> ./mothra
.NOTES
	Author: Shawn Cook
    InteliStaging Authors: Michael Tiebout, Daniel Stuetz
.LINK
	https://github.com/fa7alis/mothra
#>

param (
    [string]$Logfile  = "C:\InteliStaging.log",
    [switch]$Proceed
)

### Begin Functions ###
Function LogWrite
{
   Param ([string]$logstring)
   $stamp = Get-TimeStamp
   Write-Host "$stamp $logstring"
   Add-content $Logfile -value "$stamp $logstring"
}

## Pulls formatted date for logging
Function Get-TimeStamp {
    
    Return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)   
}


## Used to find the config directory of Symantec DLP
## Returns string with config path of Symantec DLP
Function getInstallPath {

    # Get all drives found in OS. Contains a lot of entries that are not conventional disks
    $Drives = Get-PSDrive
    Foreach ($DriveLetter in $Drives) {

        # Only check for config directory for single drive letters (ex. C, A, D)
        If ($DriveLetter -match "^[A-Z]$") {

            $Drive = "$($DriveLetter):\"    
            # Only check drives that actually have contents. This will exclude drives that are mounted but nothing is there like DVD drives with no disk
            If (Test-Path $Drive) {

                # Look for normal default install path of recent versions
                If (Test-Path "$Drive\Program Files\Symantec\DataLossPrevention\EnforceServer\15.5\Protect\config") {

                    $ConfigPath = "$($Drive)Program Files\Symantec\DataLossPrevention\EnforceServer\15.5\Protect\config"
                    If (Test-Path $ConfigPath) {
                        Write-Host "Config directory for Symantec DLP found under $ConfigPath"
                        Return $ConfigPath
                    }
                    Else { Write-Host "Install directory not found on $Drive" }
                }
                # Look for normal default install path of older versions
                Elseif (Test-Path "$Drive\SymantecDLP") {

                    $ConfigPath = "$($Drive)SymantecDLP\Protect\config"
                    If (Test-Path $ConfigPath) {
                        Write-Host "Config directory for Symantec DLP found under $ConfigPath"
                        Return $ConfigPath
                    }
                    Else { Write-Host "Install directory not found on $Drive" }
                }
                Else { Write-Host "Install directory not found on $Drive" }            
            }

        }
    }
    # Catch all statement and return value of null
    Write-Host "Install directory was not found in the default install directories. Please rerun the script with the -DLPConfig parameter specified."
    Return $null
}

Function getOracleConnectionString ([String]$ConfigDir) {

	$PropertiesFile = "$($ConfigDir)\jdbc.properties"
	$jdbcline = Get-Content $PropertiesFile | Where-Object {$_ -Like "jdbc.dbalias.oracle-thin*" }
	$linearray = $jdbcline.split('@')
	return $linearray[1]
}

### End Functions ###

### Start Main Script ###

#Checking for InteliStaging.log
Test-Path -path $Logfile
if ($Logfile){
Remove-Item $Logfile -erroraction SilentlyContinue
}

$InstallDir = getInstallPath
$tnsalias = getOracleConnectionString $InstallDir

$OraclePassword = Read-Host 'Input protect user password' -AsSecureString

$PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($OraclePassword)
$PlainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($PasswordPointer)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)

$sqlQuery = @'
    spool "c:\DetectionServerList.csv"
	select host from informationmonitor where isdeleted='0';
	spool off;
'@

$sqlQuery | sqlplus -silent protect/$PlainTextPassword@$tnsalias
### End Main Script ###

### Entering Editing File Stage###
""
Write-host "Please review DetectionServerList.csv is present and formatted correctly before moving on."
""
#Pausing script and awaiting "Enter" key
Read-Host -Prompt "Press Enter to continue"

#Loading data from CSV file
#formatting csv file
$computers = New-Object System.Collections.ArrayList
ForEach($line in (Get-Content "C:\DetectionServerList.csv")){
    if($line -match "^(?!HOST)[A-Za-z\d]+") {
        $trimmed = $line.trim()
        $computers.Add($trimmed) > $null
    }

}

#Using existing array that is loaded into PowerShell
foreach ($computer in $computers) {
    $i = 0
#Report if UNC is enabled
    If (Test-Path "\\$computer\c$") { LogWrite "UNC is enabled on $computer" }
#Reporting if UNC is disbled
    Else { LogWrite "UNC is disabled on $computer" }
$i++
Write-Progress -activity "Testing hosts for UNC . . ." -status "Tested: $i of $($computers.Count)" -percentComplete (($i / $computers.Count)  * 100)
}

#Using existing array that is loaded into PowerShell
foreach ($computer in $computers) {
    $i = 0
#Checking for staging folder on the detection servers
    If (Test-Path "\\$computer\c$\DLPStaging") { LogWrite "The directory exists on $computer" }
    Else { LogWrite "The directory does not exist $computer" }
    $i++
    Write-Progress -activity "Checking hosts for staging folder . . ." -status "Checked: $i of $($computers.Count)" -percentComplete (($i / $computers.Count)  * 100)
}
""
#Pausing script and awaiting "Enter" key
LogWrite "Review the InteliStaging.log for more details."
""
Read-Host -Prompt "Press Enter to continue - Proceed is $Proceed"

### Copying files to the detection servers###
#LogWrite "Copying the DLP installation files to the detection servers.`n"
foreach ($computer in $computers) {
    if($Proceed){
        LogWrite "Copying files to \\$computer\c$\"
        Copy-Item C:\DLPStaging -Destination \\$computer\c$\  -Recurse
        LogWrite "Copying DLP installation files to $computer is now complete." `n
    }
    else{
        #Test-Path -path C:\DLPStaging
        #LogWrite "The DLPStaging folder does not exist on $computer"
        Copy-Item C:\DLPStaging -Destination \\$computer\c$\  -Recurse -WhatIf -ErrorAction SilentlyContinue
        LogWrite "No installation files were copied to detection servers."
    }
}

### Installing Symantec DLP MSI from staging folder
foreach ($computer in $computers) {
    Invoke-Command -ComputerName $computer -ScriptBlock { 
        Start-Process c:\windows\temp\installer.exe -ArgumentList '/silent' -Wait
    }   
}

$DataStamp = get-date -Format yyyyMMddTHHmmss
$installLog = '{0}-{1}.log' -f $file.fullname,$DataStamp
$MSIArguments = @(
    "/i"
    ('"{0}"' -f $file.fullname)
    "/qn"
    "/norestart"
    "/L*v"
    $installLog
)
Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow 