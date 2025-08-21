# Windows 11 Upgrade Script - Alternative Method Using Windows Update Assistant
# This approach uses a different method that works better with remote deployment tools

param(
    [string]$LocalPath = "C:\Win11Upgrade",
    [switch]$ForceMethod = $false
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
Write-UpgradeLog "Windows 11 Upgrade - Alternative Method"
Write-UpgradeLog "========================================="

# Set bypass registry keys FIRST
Write-UpgradeLog "Setting ALL bypass registry keys"

# Create all necessary registry paths
$registryPaths = @(
    "HKLM:\SYSTEM\Setup\MoSetup"
    "HKLM:\SYSTEM\Setup\LabConfig"
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"
)

foreach ($path in $registryPaths) {
    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
        Write-UpgradeLog "Created: $path"
    }
}

# MoSetup keys
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force

# LabConfig keys - comprehensive bypass
$labConfigKeys = @{
    "BypassTPMCheck" = 1
    "BypassSecureBootCheck" = 1
    "BypassRAMCheck" = 1
    "BypassStorageCheck" = 1
    "BypassCPUCheck" = 1
    "BypassDiskCheck" = 1
}

foreach ($key in $labConfigKeys.Keys) {
    Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\LabConfig" -Name $key -Value $labConfigKeys[$key] -Type DWord -Force
}

# OOBE keys for silent setup
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "BypassNRO" -Value 1 -Type DWord -Force

Write-UpgradeLog "All bypass keys set successfully"

# METHOD 1: Try using setupprep.exe first (more reliable for silent upgrades)
$SetupPrepPath = "$LocalPath\sources\setupprep.exe"
if (Test-Path $SetupPrepPath) {
    Write-UpgradeLog "Found setupprep.exe - using advanced method"
    
    try {
        # Copy setupprep to Windows\Temp (sometimes helps with permissions)
        $TempSetupPrep = "$env:windir\Temp\setupprep.exe"
        Copy-Item $SetupPrepPath -Destination $TempSetupPrep -Force
        
        # Run setupprep with minimal UI
        $prepArgs = "/Auto Upgrade /Quiet /NoReboot"
        
        Write-UpgradeLog "Executing: $TempSetupPrep $prepArgs"
        
        $process = Start-Process -FilePath $TempSetupPrep -ArgumentList $prepArgs -PassThru -Wait
        $exitCode = $process.ExitCode
        
        Write-UpgradeLog "SetupPrep exit code: $exitCode"
        
        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            Write-UpgradeLog "SUCCESS: Upgrade initiated via setupprep"
            exit 0
        }
    } catch {
        Write-UpgradeLog "SetupPrep method failed: $_"
    }
}

# METHOD 2: Use setup.exe with configuration file
Write-UpgradeLog "Attempting setup.exe with configuration file"

# Create a setup configuration file
$configContent = @"
[SetupConfig]
BitLocker=AlwaysSuspend
Compat=IgnoreWarning
Priority=Normal
DynamicUpdate=Disable
ShowOOBE=None
Telemetry=Disable
NoReboot
"@

$configPath = "$LocalPath\setupconfig.ini"
$configContent | Out-File -FilePath $configPath -Encoding ASCII
Write-UpgradeLog "Created setupconfig.ini"

# Verify setup.exe exists
$SetupPath = "$LocalPath\setup.exe"
if (!(Test-Path $SetupPath)) {
    Write-UpgradeLog "ERROR: setup.exe not found"
    exit 1
}

# METHOD 2A: Try with config file reference
try {
    $setupArgs = "/Auto Upgrade /ConfigFile `"$configPath`""
    
    Write-UpgradeLog "Executing: $SetupPath $setupArgs"
    
    # Use WMI to create process (sometimes works better for silent execution)
    $startInfo = ([wmiclass]"Win32_ProcessStartup").CreateInstance()
    $startInfo.ShowWindow = 0  # Hidden window
    
    $result = ([wmiclass]"Win32_Process").Create("$SetupPath $setupArgs", $LocalPath, $startInfo)
    
    if ($result.ReturnValue -eq 0) {
        Write-UpgradeLog "Process created successfully with PID: $($result.ProcessId)"
        
        # Wait for process to complete or at least start properly
        Start-Sleep -Seconds 30
        
        # Check if setup is running
        $setupProcess = Get-Process -Name "SetupHost", "Setup" -ErrorAction SilentlyContinue
        if ($setupProcess) {
            Write-UpgradeLog "SUCCESS: Windows 11 setup is running"
            Write-UpgradeLog "The upgrade will continue in the background"
            exit 0
        }
    } else {
        Write-UpgradeLog "Failed to create process. Return value: $($result.ReturnValue)"
    }
} catch {
    Write-UpgradeLog "Config file method failed: $_"
}

# METHOD 3: Create and execute a batch file (sometimes bypasses parameter parsing issues)
Write-UpgradeLog "Attempting batch file method"

$batchContent = @"
@echo off
cd /d "$LocalPath"
start "" /B setup.exe /Auto Upgrade /Quiet /NoReboot /DynamicUpdate Disable /MigrateDrivers All /ShowOOBE None /Compat IgnoreWarning
exit
"@

$batchPath = "$LocalPath\run_upgrade.bat"
$batchContent | Out-File -FilePath $batchPath -Encoding ASCII
Write-UpgradeLog "Created batch file: $batchPath"

try {
    # Run the batch file hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"$batchPath`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    
    $process = [System.Diagnostics.Process]::Start($psi)
    
    # Give it time to start
    Start-Sleep -Seconds 10
    
    # Check if setup started
    $setupProcess = Get-Process -Name "SetupHost", "Setup" -ErrorAction SilentlyContinue
    if ($setupProcess) {
        Write-UpgradeLog "SUCCESS: Setup started via batch file"
        exit 0
    }
} catch {
    Write-UpgradeLog "Batch file method failed: $_"
}

# METHOD 4: Last resort - Create a system-level scheduled task
if ($ForceMethod) {
    Write-UpgradeLog "Using forced scheduled task method"
    
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>$(Get-Date -Format yyyy-MM-ddTHH:mm:ss)</Date>
    <Author>NT AUTHORITY\SYSTEM</Author>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$(Get-Date -Format yyyy-MM-ddTHH:mm:ss)</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Hidden>true</Hidden>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT4H</ExecutionTimeLimit>
    <Priority>4</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$SetupPath</Command>
      <Arguments>/Auto Upgrade /Quiet /NoReboot</Arguments>
      <WorkingDirectory>$LocalPath</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
    
    $taskXml | Out-File -FilePath "$LocalPath\upgrade_task.xml" -Encoding Unicode
    
    # Import the task
    schtasks /Create /TN "Win11UpgradeForced" /XML "$LocalPath\upgrade_task.xml" /F
    schtasks /Run /TN "Win11UpgradeForced"
    
    Write-UpgradeLog "Forced scheduled task created and started"
}

Write-UpgradeLog "========================================="
Write-UpgradeLog "All methods attempted - check logs"
Write-UpgradeLog "If upgrade hasn't started, try running with -ForceMethod switch"
Write-UpgradeLog "==========================================="
