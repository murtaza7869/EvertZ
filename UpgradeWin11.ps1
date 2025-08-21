# Windows 11 Upgrade Script - Enterprise Deployment Version
# This script handles the context and elevation issues for silent upgrades

param(
    [string]$SourcePath = "\\YourServer\Share\Windows11",
    [string]$LocalPath = "C:\Windows11Upgrade",
    [switch]$ForceReboot = $false
)

# Function to write logs
function Write-UpgradeLog {
    param($Message)
    $LogPath = "$LocalPath\upgrade_log.txt"
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogPath -Append
    Write-Host $Message
}

# Create local directory
Write-UpgradeLog "Starting Windows 11 Upgrade Process"
if (!(Test-Path $LocalPath)) {
    New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
}

# Set TPM and Secure Boot bypass registry keys
Write-UpgradeLog "Setting bypass registry keys"
$RegistryPath = "HKLM:\SYSTEM\Setup\MoSetup"
if (!(Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
Set-ItemProperty -Path $RegistryPath -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force

# Additional bypass keys for Windows 11
$LabConfigPath = "HKLM:\SYSTEM\Setup\LabConfig"
if (!(Test-Path $LabConfigPath)) {
    New-Item -Path $LabConfigPath -Force | Out-Null
}
Set-ItemProperty -Path $LabConfigPath -Name "BypassTPMCheck" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $LabConfigPath -Name "BypassSecureBootCheck" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $LabConfigPath -Name "BypassRAMCheck" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $LabConfigPath -Name "BypassStorageCheck" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $LabConfigPath -Name "BypassCPUCheck" -Value 1 -Type DWord -Force

# Copy Windows 11 setup files
Write-UpgradeLog "Copying Windows 11 setup files from $SourcePath"
try {
    $CopyParams = @{
        Path = "$SourcePath\*"
        Destination = $LocalPath
        Recurse = $true
        Force = $true
        ErrorAction = "Stop"
    }
    Copy-Item @CopyParams
    Write-UpgradeLog "Files copied successfully"
} catch {
    Write-UpgradeLog "ERROR: Failed to copy files - $_"
    exit 1
}

# Verify setup.exe exists
$SetupPath = "$LocalPath\setup.exe"
if (!(Test-Path $SetupPath)) {
    Write-UpgradeLog "ERROR: setup.exe not found at $SetupPath"
    exit 1
}

# Create auto-answer file for better silent installation
$AutoUnattendContent = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UserData>
                <AcceptEula>true</AcceptEula>
            </UserData>
            <UpgradeData>
                <Upgrade>true</Upgrade>
                <WillWipeDisk>false</WillWipeDisk>
            </UpgradeData>
        </component>
    </settings>
</unattend>
'@
$AutoUnattendContent | Out-File -FilePath "$LocalPath\autounattend.xml" -Encoding UTF8

# CRITICAL FIX: Use different approach based on execution context
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isSystem = $currentUser.Name -eq "NT AUTHORITY\SYSTEM"

if ($isSystem) {
    Write-UpgradeLog "Running as SYSTEM - using scheduled task approach"
    
    # Create a scheduled task to run in user context
    $TaskName = "Windows11UpgradeTask"
    
    # Get the currently logged-on user
    $LoggedOnUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if (!$LoggedOnUser) {
        Write-UpgradeLog "ERROR: No user currently logged on"
        exit 1
    }
    
    # Create the action for the scheduled task
    $Action = New-ScheduledTaskAction -Execute $SetupPath -Argument "/auto upgrade /dynamicupdate disable /migratedrivers all /showoobe none /compat ignorewarning /copylogs $LocalPath"
    
    # Create trigger to run immediately
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
    
    # Create principal to run as logged-on user
    $Principal = New-ScheduledTaskPrincipal -UserId $LoggedOnUser -LogonType Interactive -RunLevel Highest
    
    # Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force
    
    Write-UpgradeLog "Scheduled task created - will run in 10 seconds"
    
    # Wait for task to start
    Start-Sleep -Seconds 15
    
    # Monitor task
    $timeout = 300 # 5 minutes to start
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task.State -eq "Running") {
            Write-UpgradeLog "Upgrade task is running"
            break
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    
} else {
    Write-UpgradeLog "Running in user context - executing setup directly"
    
    # Build setup arguments - NOTE: Using /silent instead of /quiet
    $SetupArgs = @(
        "/auto", "upgrade"
        "/dynamicupdate", "disable"
        "/migratedrivers", "all"
        "/showoobe", "none"
        "/compat", "ignorewarning"
        "/copylogs", $LocalPath
        "/silent"  # Use /silent instead of /quiet
    )
    
    if ($ForceReboot) {
        $SetupArgs += "/forcereboot"
    } else {
        $SetupArgs += "/noreboot"
    }
    
    Write-UpgradeLog "Starting setup.exe with arguments: $($SetupArgs -join ' ')"
    
    # Start the setup process
    $SetupProcess = Start-Process -FilePath $SetupPath -ArgumentList $SetupArgs -PassThru -Wait
    
    Write-UpgradeLog "Setup.exe exit code: $($SetupProcess.ExitCode)"
    
    # Check common exit codes
    switch ($SetupProcess.ExitCode) {
        0 { Write-UpgradeLog "SUCCESS: Upgrade completed successfully" }
        3010 { Write-UpgradeLog "SUCCESS: Upgrade completed - reboot required" }
        1641 { Write-UpgradeLog "SUCCESS: Upgrade started - reboot initiated" }
        -1047526896 { Write-UpgradeLog "ERROR: Compatibility issues detected" }
        -1047526904 { Write-UpgradeLog "ERROR: Insufficient disk space" }
        default { Write-UpgradeLog "Setup completed with exit code: $($SetupProcess.ExitCode)" }
    }
}

# Copy logs for analysis
$LogFiles = @("setuperr.log", "setupact.log", "Bluebox.log", "Panther\*.log")
foreach ($log in $LogFiles) {
    $sourceLogs = Get-ChildItem -Path "$env:SystemDrive\`$WINDOWS.~BT\Sources\Panther\$log" -ErrorAction SilentlyContinue
    if ($sourceLogs) {
        Copy-Item $sourceLogs.FullName -Destination $LocalPath -Force
    }
}

Write-UpgradeLog "Upgrade process completed - check logs in $LocalPath"
