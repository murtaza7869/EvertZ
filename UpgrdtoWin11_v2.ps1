# Windows 11 Upgrade Script - Local Files Version
# This script assumes Windows 11 files are already at C:\Win11Upgrade
# Handles context and elevation issues for silent upgrades

param(
    [string]$LocalPath = "C:\Win11Upgrade",
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

Write-UpgradeLog "========================================="
Write-UpgradeLog "Starting Windows 11 Upgrade Process"
Write-UpgradeLog "========================================="

# Verify setup files exist
$SetupPath = "$LocalPath\setup.exe"
if (!(Test-Path $SetupPath)) {
    Write-UpgradeLog "ERROR: setup.exe not found at $SetupPath"
    Write-UpgradeLog "Please ensure Windows 11 installation files are present at $LocalPath"
    exit 1
}
Write-UpgradeLog "Setup.exe found at $SetupPath"

# Set TPM and Secure Boot bypass registry keys
Write-UpgradeLog "Setting bypass registry keys for TPM and Secure Boot"

# MoSetup registry path
$RegistryPath = "HKLM:\SYSTEM\Setup\MoSetup"
if (!(Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
    Write-UpgradeLog "Created registry path: $RegistryPath"
}
Set-ItemProperty -Path $RegistryPath -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force

# LabConfig registry path - More comprehensive bypasses
$LabConfigPath = "HKLM:\SYSTEM\Setup\LabConfig"
if (!(Test-Path $LabConfigPath)) {
    New-Item -Path $LabConfigPath -Force | Out-Null
    Write-UpgradeLog "Created registry path: $LabConfigPath"
}

# Set all bypass keys
$bypassKeys = @{
    "BypassTPMCheck" = 1
    "BypassSecureBootCheck" = 1
    "BypassRAMCheck" = 1
    "BypassStorageCheck" = 1
    "BypassCPUCheck" = 1
}

foreach ($key in $bypassKeys.Keys) {
    Set-ItemProperty -Path $LabConfigPath -Name $key -Value $bypassKeys[$key] -Type DWord -Force
    Write-UpgradeLog "Set $key = 1"
}

# Create auto-answer file for better silent installation
Write-UpgradeLog "Creating autounattend.xml file"
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

# Check current execution context
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isSystem = $currentUser.Name -eq "NT AUTHORITY\SYSTEM"
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

Write-UpgradeLog "Current user: $($currentUser.Name)"
Write-UpgradeLog "Is SYSTEM: $isSystem"
Write-UpgradeLog "Is Admin: $isAdmin"

# CRITICAL FIX: Handle different execution contexts
if ($isSystem) {
    Write-UpgradeLog "Running as SYSTEM - using scheduled task approach for user context"
    
    # Get the currently logged-on user
    $LoggedOnUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if (!$LoggedOnUser) {
        # Alternative method to get logged on user
        $LoggedOnUser = (Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object {$_.GetOwner().User} | Select-Object -First 1)
        if (!$LoggedOnUser) {
            Write-UpgradeLog "ERROR: No interactive user session detected"
            Write-UpgradeLog "Windows 11 upgrade requires an active user session"
            exit 1
        }
    }
    
    Write-UpgradeLog "Detected logged-on user: $LoggedOnUser"
    
    # Create a scheduled task to run in user context
    $TaskName = "Windows11UpgradeTask_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Build setup arguments for scheduled task
    $SetupArgs = "/auto upgrade /dynamicupdate disable /migratedrivers all /showoobe none /compat ignorewarning /copylogs $LocalPath /silent"
    if (!$ForceReboot) {
        $SetupArgs += " /noreboot"
    }
    
    # Create the action for the scheduled task
    $Action = New-ScheduledTaskAction -Execute $SetupPath -Argument $SetupArgs
    
    # Create trigger to run immediately
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
    
    # Create settings
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 4
    
    # Create principal to run as logged-on user with highest privileges
    $Principal = New-ScheduledTaskPrincipal -UserId $LoggedOnUser -LogonType Interactive -RunLevel Highest
    
    # Register the task
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force
        Write-UpgradeLog "Scheduled task '$TaskName' created successfully"
    } catch {
        Write-UpgradeLog "ERROR: Failed to create scheduled task - $_"
        exit 1
    }
    
    # Start the task
    Start-Sleep -Seconds 11
    Start-ScheduledTask -TaskName $TaskName
    Write-UpgradeLog "Scheduled task started"
    
    # Monitor task execution
    $timeout = 300 # 5 minutes to start
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($task.State -eq "Running") {
            Write-UpgradeLog "Upgrade task is running..."
            # Once running, exit the script and let the upgrade continue
            Write-UpgradeLog "Setup.exe is now running in user context"
            Write-UpgradeLog "The upgrade will continue in the background"
            break
        } elseif ($task.State -eq "Ready" -and $taskInfo.LastRunTime) {
            Write-UpgradeLog "Task completed with result: $($taskInfo.LastTaskResult)"
            break
        }
        
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
    
    if ($elapsed -ge $timeout) {
        Write-UpgradeLog "WARNING: Task monitoring timeout reached"
    }
    
} else {
    Write-UpgradeLog "Running in user context - executing setup directly"
    
    # Build setup arguments - Using /silent instead of /quiet
    $SetupArgs = @(
        "/auto", "upgrade"
        "/dynamicupdate", "disable"
        "/migratedrivers", "all"
        "/showoobe", "none"
        "/compat", "ignorewarning"
        "/copylogs", $LocalPath
        "/silent"  # Use /silent instead of /quiet for better compatibility
    )
    
    if ($ForceReboot) {
        $SetupArgs += "/forcereboot"
    } else {
        $SetupArgs += "/noreboot"
    }
    
    Write-UpgradeLog "Executing: $SetupPath"
    Write-UpgradeLog "Arguments: $($SetupArgs -join ' ')"
    
    # Alternative method: Run setup.exe using Start-Process with specific window style
    try {
        # First attempt - using Start-Process with hidden window
        $SetupProcess = Start-Process -FilePath $SetupPath -ArgumentList $SetupArgs -WindowStyle Hidden -PassThru -Wait
        $exitCode = $SetupProcess.ExitCode
        
    } catch {
        Write-UpgradeLog "First attempt failed, trying alternative method"
        
        # Alternative method using .NET Process class for better control
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SetupPath
            $psi.Arguments = $SetupArgs -join " "
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            
            $process = [System.Diagnostics.Process]::Start($psi)
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            
        } catch {
            Write-UpgradeLog "ERROR: Failed to start setup.exe - $_"
            exit 1
        }
    }
    
    Write-UpgradeLog "Setup.exe exit code: $exitCode"
    
    # Interpret exit codes
    switch ($exitCode) {
        0 { 
            Write-UpgradeLog "SUCCESS: Upgrade completed successfully"
            Write-UpgradeLog "A reboot may still be required to complete the upgrade"
        }
        1 { Write-UpgradeLog "ERROR: General failure" }
        2 { Write-UpgradeLog "ERROR: Invalid command line parameters" }
        3010 { 
            Write-UpgradeLog "SUCCESS: Upgrade completed - reboot required"
            Write-UpgradeLog "Please reboot the system to complete the upgrade"
        }
        1641 { 
            Write-UpgradeLog "SUCCESS: Upgrade started - reboot initiated"
        }
        3221225786 { Write-UpgradeLog "ERROR: The upgrade was cancelled" }
        -1047526896 { Write-UpgradeLog "ERROR: Compatibility issues detected" }
        -1047526904 { Write-UpgradeLog "ERROR: Insufficient disk space" }
        -1047527168 { Write-UpgradeLog "ERROR: Unknown compatibility issue" }
        -2147024891 { Write-UpgradeLog "ERROR: Access denied - admin rights required" }
        default { 
            Write-UpgradeLog "Setup completed with exit code: $exitCode"
            Write-UpgradeLog "Check the setup logs for more details"
        }
    }
}

# Attempt to copy setup logs for analysis
Write-UpgradeLog "Attempting to copy setup logs..."

$LogLocations = @(
    "$env:SystemDrive\`$WINDOWS.~BT\Sources\Panther",
    "$env:SystemDrive\Windows\Panther",
    "$env:SystemDrive\`$Windows.~WS\Sources\Panther",
    "$env:TEMP"
)

$LogFiles = @("setupact.log", "setuperr.log", "setupapi.dev.log", "miglog.xml", "BlueBox.log")

foreach ($location in $LogLocations) {
    foreach ($logFile in $LogFiles) {
        $sourcePath = Join-Path $location $logFile
        if (Test-Path $sourcePath) {
            $destPath = Join-Path $LocalPath "$(Get-Date -Format 'yyyyMMdd_HHmmss')_$logFile"
            try {
                Copy-Item $sourcePath -Destination $destPath -Force -ErrorAction SilentlyContinue
                Write-UpgradeLog "Copied $logFile from $location"
            } catch {
                # Silent continue
            }
        }
    }
}

Write-UpgradeLog "========================================="
Write-UpgradeLog "Upgrade process completed"
Write-UpgradeLog "Check logs in $LocalPath for details"
Write-UpgradeLog "========================================="

# Create a summary file for Deploy reporting
$summaryContent = @{
    "Timestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "Computer" = $env:COMPUTERNAME
    "User" = $currentUser.Name
    "SetupPath" = $SetupPath
    "ExecutionContext" = if ($isSystem) { "SYSTEM" } else { "USER" }
    "LogPath" = "$LocalPath\upgrade_log.txt"
}

$summaryContent | ConvertTo-Json | Out-File -FilePath "$LocalPath\upgrade_summary.json" -Encoding UTF8
