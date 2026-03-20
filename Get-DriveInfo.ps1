#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive SSD / Physical Drive Information Collector
    For use in diagnosing disk health issues on Windows 11
.NOTES
    Run as Administrator in PowerShell 5.1 or PowerShell 7+
    Output is saved to the same folder the script is run from.
    Usage:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        .\Get-DriveInfo.ps1
#>

$OutputFile = "$PSScriptRoot\DriveReport_$(hostname)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Report     = [System.Collections.Generic.List[string]]::new()

function Write-Section {
    param([string]$Title)
    $line = "=" * 65
    $Report.Add("")
    $Report.Add($line)
    $Report.Add("  $Title")
    $Report.Add($line)
    Write-Host ""
    Write-Host $line           -ForegroundColor Cyan
    Write-Host "  $Title"      -ForegroundColor Cyan
    Write-Host $line           -ForegroundColor Cyan
}

function Add-Line {
    param([string]$Text, [ConsoleColor]$Color = "White")
    $Report.Add($Text)
    Write-Host $Text -ForegroundColor $Color
}

function Add-KV {
    param([string]$Key, $Value, [ConsoleColor]$Color = "White")
    $line = "  {0,-35} {1}" -f ($Key + " :"), $Value
    $Report.Add($line)
    Write-Host $line -ForegroundColor $Color
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
$Report.Add("DRIVE DIAGNOSTIC REPORT")
$Report.Add("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Report.Add("Hostname  : $(hostname)")
$Report.Add("User      : $env:USERNAME")
Write-Host ""
Write-Host "DRIVE DIAGNOSTIC REPORT -- $(hostname)" -ForegroundColor Yellow
Write-Host "Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Section 1 - Physical Disk Summary
# ---------------------------------------------------------------------------
Write-Section "1. PHYSICAL DISK SUMMARY"

try {
    $physDisks = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($disk in $physDisks) {
        Add-Line ""
        Add-KV "Disk Index"          $disk.DeviceId
        Add-KV "Friendly Name"       $disk.FriendlyName
        Add-KV "Serial Number"       $disk.SerialNumber
        Add-KV "Media Type"          $disk.MediaType
        Add-KV "Bus Type"            $disk.BusType
        Add-KV "Size"                ("{0:N2} GB" -f ($disk.Size / 1GB))
        Add-KV "Health Status"       $disk.HealthStatus
        Add-KV "Operational Status"  $disk.OperationalStatus
        Add-KV "Firmware Version"    $disk.FirmwareVersion
        $spindle = if ($disk.SpindleSpeed -eq 0) { "N/A (SSD)" } else { "$($disk.SpindleSpeed) RPM" }
        Add-KV "Spindle Speed"       $spindle

        $hColor = switch ($disk.HealthStatus) {
            "Healthy"   { "Green"  }
            "Warning"   { "Yellow" }
            "Unhealthy" { "Red"    }
            default     { "White"  }
        }
        Write-Host ("  {0,-35} {1}" -f "Health Status :", $disk.HealthStatus) -ForegroundColor $hColor
    }
} catch {
    Add-Line "  [ERROR] Could not retrieve physical disk info: $_" "Red"
}

# ---------------------------------------------------------------------------
# Section 2 - Disk and Partition Layout
# ---------------------------------------------------------------------------
Write-Section "2. DISK AND PARTITION LAYOUT"

try {
    $disks = Get-Disk | Sort-Object Number
    foreach ($d in $disks) {
        Add-Line ""
        Add-KV "Disk Number"      $d.Number
        Add-KV "Friendly Name"    $d.FriendlyName
        Add-KV "Partition Style"  $d.PartitionStyle
        Add-KV "Total Size"       ("{0:N2} GB" -f ($d.Size / 1GB))
        Add-KV "Allocated Size"   ("{0:N2} GB" -f ($d.AllocatedSize / 1GB))
        Add-KV "Boot Disk"        $d.IsBoot
        Add-KV "System Disk"      $d.IsSystem
        Add-KV "Read Only"        $d.IsReadOnly

        $partitions = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
        foreach ($p in $partitions) {
            $vol    = Get-Volume -Partition $p -ErrorAction SilentlyContinue
            $label  = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(no label)"   }
            $letter = if ($p.DriveLetter)        { "$($p.DriveLetter):"  } else { "(no letter)" }
            $fs     = if ($vol.FileSystem)        { $vol.FileSystem }       else { "RAW/Unknown" }
            $free   = if ($vol.SizeRemaining)     { "{0:N2} GB free" -f ($vol.SizeRemaining / 1GB) } else { "N/A" }
            $psize  = "{0:N2} GB" -f ($p.Size / 1GB)
            Add-Line ("    Partition {0}  {1}  {2}  {3}  FS={4}  {5}" -f `
                $p.PartitionNumber, $letter, $label, $psize, $fs, $free)
        }
    }
} catch {
    Add-Line "  [ERROR] Could not retrieve disk layout: $_" "Red"
}

# ---------------------------------------------------------------------------
# Section 3 - SMART Status via WMI
# ---------------------------------------------------------------------------
Write-Section "3. SMART STATUS (WMI)"

try {
    $smartStatus = Get-WmiObject -Namespace root\wmi `
        -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
    foreach ($s in $smartStatus) {
        Add-KV "Instance"          $s.InstanceName
        Add-KV "SMART Active"      $s.Active
        Add-KV "Predicted Failure" $s.PredictFailure
        if ($s.PredictFailure -eq $true) {
            Add-Line "  *** WARNING: Drive is predicting imminent failure! ***" "Red"
        } else {
            Add-Line "  SMART Prediction: OK" "Green"
        }
        Add-Line ""
    }
} catch {
    Add-Line "  [INFO] MSStorageDriver_FailurePredictStatus not available (common on NVMe)." "Yellow"
    Add-Line "         Use CrystalDiskInfo or the manufacturer tool for NVMe SMART data."    "Yellow"
}

# ---------------------------------------------------------------------------
# Section 4 - SMART Raw Attribute Data
# ---------------------------------------------------------------------------
Write-Section "4. SMART RAW ATTRIBUTE DATA (WMI)"

try {
    $smartData = Get-WmiObject -Namespace root\wmi `
        -Class MSStorageDriver_FailurePredictData -ErrorAction Stop

    $knownAttrs = @{
        1   = "Read Error Rate"
        3   = "Spin-Up Time"
        4   = "Start/Stop Count"
        5   = "Reallocated Sectors Count"
        7   = "Seek Error Rate"
        9   = "Power-On Hours"
        10  = "Spin Retry Count"
        12  = "Power Cycle Count"
        160 = "Uncorrectable Errors"
        161 = "Valid Spare Blocks"
        163 = "Initial Bad Block Count"
        164 = "Total Erase Count"
        165 = "Max Erase Count"
        166 = "Min Erase Count"
        167 = "Average Erase Count"
        168 = "Max NAND Erase Count"
        169 = "Remaining Life Pct"
        171 = "SSD Program Fail Count"
        172 = "SSD Erase Fail Count"
        173 = "SSD Wear Level Count"
        174 = "Unexpected Power Loss"
        177 = "Wear Leveling Count"
        179 = "Used Reserved Block Count"
        180 = "Unused Reserved Block Count"
        181 = "Program Fail Count Total"
        182 = "Erase Fail Count Total"
        183 = "Runtime Bad Block"
        184 = "End-to-End Error"
        187 = "Uncorrectable Error Count"
        188 = "Command Timeout"
        190 = "Airflow Temperature"
        192 = "Power-off Retract Count"
        193 = "Load/Unload Cycle Count"
        194 = "Temperature (Celsius)"
        196 = "Reallocation Event Count"
        197 = "Current Pending Sector Count"
        198 = "Uncorrectable Sector Count"
        199 = "UltraDMA CRC Error Count"
        200 = "Write Error Rate"
        231 = "SSD Life Left"
        232 = "Endurance Remaining"
        233 = "Media Wearout Indicator"
        241 = "Total LBAs Written"
        242 = "Total LBAs Read"
        251 = "Minimum Spares Remaining"
    }

    # These must be 0 on a healthy SSD
    $criticalAttrs = @(5, 171, 172, 187, 197, 198)

    foreach ($sd in $smartData) {
        Add-KV "Instance" $sd.InstanceName
        $raw = $sd.VendorSpecific
        if ($raw -and $raw.Count -ge 12) {
            Add-Line "  Attr# Name                            Flags  Value  Worst  Raw"
            Add-Line "  ----- ------------------------------- -----  -----  -----  ---"
            for ($i = 2; $i -lt [Math]::Min($raw.Count, 362); $i += 12) {
                $attrId = $raw[$i]
                if ($attrId -eq 0) { continue }
                $flags  = ($raw[$i+1]) -bor ($raw[$i+2] -shl 8)
                $value  = $raw[$i+3]
                $worst  = $raw[$i+4]
                $rawVal = [long]$raw[$i+5]               `
                        -bor ([long]$raw[$i+6]  -shl  8) `
                        -bor ([long]$raw[$i+7]  -shl 16) `
                        -bor ([long]$raw[$i+8]  -shl 24) `
                        -bor ([long]$raw[$i+9]  -shl 32) `
                        -bor ([long]$raw[$i+10] -shl 40)

                $name  = if ($knownAttrs.ContainsKey([int]$attrId)) {
                             $knownAttrs[[int]$attrId]
                         } else {
                             "Attr $attrId"
                         }
                $line  = "  {0,5}  {1,-31} 0x{2:X4}  {3,5}  {4,5}  {5}" -f `
                         $attrId, $name, $flags, $value, $worst, $rawVal

                $isCrit = $criticalAttrs -contains [int]$attrId
                if ($isCrit -and $rawVal -gt 0) {
                    $Report.Add($line + "  <<< WARNING")
                    Write-Host ($line + "  <<< WARNING") -ForegroundColor Red
                } elseif ($isCrit) {
                    $Report.Add($line)
                    Write-Host $line -ForegroundColor Green
                } else {
                    $Report.Add($line)
                    Write-Host $line -ForegroundColor Gray
                }
            }
        }
        Add-Line ""
    }
} catch {
    Add-Line "  [INFO] SMART raw data not available via WMI (typical for NVMe)." "Yellow"
    Add-Line "         Run CrystalDiskInfo for full NVMe SMART attributes."       "Yellow"
}

# ---------------------------------------------------------------------------
# Section 5 - NVMe Health via StorageSubSystem
# ---------------------------------------------------------------------------
Write-Section "5. STORAGE SUBSYSTEM AND NVMe HEALTH"

try {
    $subsystems = Get-StorageSubSystem -ErrorAction Stop
    foreach ($sub in $subsystems) {
        Add-KV "Subsystem"           $sub.FriendlyName
        Add-KV "Health Status"       $sub.HealthStatus
        Add-KV "Operational Status"  $sub.OperationalStatus
        Add-KV "Description"         $sub.Description
        Add-Line ""
    }
} catch {
    Add-Line "  [INFO] StorageSubSystem cmdlet not available on this configuration." "Yellow"
}

try {
    $nvmeDevs = Get-WmiObject -Namespace root\wmi `
        -Class NVMe_Device_Self_Test -ErrorAction Stop
    Add-Line "  NVMe Self-Test devices found: $($nvmeDevs.Count)"
} catch {
    Add-Line "  [INFO] NVMe WMI self-test class not present. Use manufacturer tool." "Yellow"
}

# ---------------------------------------------------------------------------
# Section 6 - Volume Health and Free Space
# ---------------------------------------------------------------------------
Write-Section "6. VOLUME HEALTH AND FREE SPACE"

try {
    $vols = Get-Volume |
        Where-Object { $_.DriveType -ne "CD-ROM" -and $_.DriveLetter } |
        Sort-Object DriveLetter

    foreach ($v in $vols) {
        $pctFree = if ($v.Size -gt 0) {
            [math]::Round(($v.SizeRemaining / $v.Size) * 100, 1)
        } else { 0 }

        $color = if ($pctFree -lt 10) { "Red" } elseif ($pctFree -lt 20) { "Yellow" } else { "White" }

        Add-Line ""
        Add-KV "Drive Letter"   "$($v.DriveLetter):"
        Add-KV "Label"          $v.FileSystemLabel
        Add-KV "File System"    $v.FileSystem
        Add-KV "Drive Type"     $v.DriveType
        Add-KV "Total Size"     ("{0:N2} GB" -f ($v.Size / 1GB))
        Add-KV "Free Space"     ("{0:N2} GB  ({1} pct free)" -f ($v.SizeRemaining / 1GB), $pctFree) $color
        Add-KV "Health Status"  $v.HealthStatus
    }
} catch {
    Add-Line "  [ERROR] Could not retrieve volume info: $_" "Red"
}

# ---------------------------------------------------------------------------
# Section 7 - Disk Error Events (last 7 days)
# ---------------------------------------------------------------------------
Write-Section "7. DISK / STORAGE ERROR EVENTS (last 7 days)"

try {
    $since     = (Get-Date).AddDays(-7)
    $providers = "disk|volmgr|stornvme|storahci|ntfs|fastfat|partmgr|nvmedisk"

    $diskEvents = Get-WinEvent -LogName System -ErrorAction Stop |
        Where-Object {
            $_.TimeCreated -ge $since -and
            $_.LevelDisplayName -in @("Error","Critical","Warning") -and
            $_.ProviderName -match $providers
        } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 50

    if ($diskEvents) {
        foreach ($ev in $diskEvents) {
            $msg  = ($ev.Message -split "`n")[0].Trim()
            $line = "[{0}] ID={1,-6} Source={2,-25} {3}" -f `
                $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"),
                $ev.Id,
                $ev.ProviderName,
                $msg
            $col = if ($ev.LevelDisplayName -in @("Error","Critical")) { "Red" } else { "Yellow" }
            $Report.Add("  " + $line)
            Write-Host ("  " + $line) -ForegroundColor $col
        }
    } else {
        Add-Line "  No disk/storage errors found in the last 7 days." "Green"
    }
} catch {
    Add-Line "  [ERROR] Could not query event log: $_" "Red"
}

# ---------------------------------------------------------------------------
# Section 8 - chkdsk Status
# ---------------------------------------------------------------------------
Write-Section "8. CHKDSK STATUS"

try {
    $regPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $chkdskReg = Get-ItemProperty $regPath -Name BootExecute -ErrorAction Stop
    $bootExec  = $chkdskReg.BootExecute -join " "
    Add-KV "BootExecute entry" $bootExec
    if ($bootExec -match "chkdsk") {
        Add-Line "  *** chkdsk IS scheduled to run on next reboot ***" "Yellow"
    } else {
        Add-Line "  chkdsk is NOT currently scheduled." "Green"
    }
} catch {
    Add-Line "  [ERROR] Could not read BootExecute registry key: $_" "Red"
}

try {
    $chkdskEvent = Get-WinEvent -LogName Application -ErrorAction Stop |
        Where-Object {
            $_.Id -eq 26212 -and
            $_.ProviderName -eq "Microsoft-Windows-Wininit"
        } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 1

    if ($chkdskEvent) {
        Add-Line ""
        Add-KV "Last chkdsk run" $chkdskEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        Add-Line "  Result (first 600 chars):"
        Add-Line ("  " + $chkdskEvent.Message.Substring(0, [Math]::Min(600, $chkdskEvent.Message.Length)))
    } else {
        Add-Line "  No previous chkdsk result found in Application log (EventID 26212)." "Yellow"
    }
} catch {
    Add-Line "  [INFO] Could not retrieve chkdsk history from event log." "Yellow"
}

# ---------------------------------------------------------------------------
# Section 9 - Pagefile and CrashControl
# ---------------------------------------------------------------------------
Write-Section "9. PAGEFILE AND CRASHCONTROL SETTINGS"

try {
    $cc = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction Stop

    $dumpTypes = @{
        0 = "Disabled"
        1 = "Complete Memory Dump"
        2 = "Kernel Memory Dump"
        3 = "Small (Minidump only)"
        7 = "Automatic Memory Dump"
    }
    $dumpDesc = if ($dumpTypes.ContainsKey([int]$cc.CrashDumpEnabled)) {
        $dumpTypes[[int]$cc.CrashDumpEnabled]
    } else { "Unknown" }

    Add-KV "CrashDumpEnabled"     "$($cc.CrashDumpEnabled) -- $dumpDesc"
    Add-KV "DumpFile"             $cc.DumpFile
    Add-KV "MinidumpDir"          $cc.MinidumpDir
    Add-KV "AutoReboot"           $cc.AutoReboot
    Add-KV "AlwaysKeepMemoryDump" $cc.AlwaysKeepMemoryDump

    $pfSmall = $cc.PagefileTooSmall
    if ($pfSmall -and [long]$pfSmall -ne 0) {
        Add-KV "PagefileTooSmall" "YES -- MEMORY.DMP WILL NOT BE WRITTEN" "Red"
        Add-Line "  *** ACTION REQUIRED: Increase pagefile to at least RAM size ***" "Red"
    } else {
        Add-KV "PagefileTooSmall" "No -- pagefile size is OK" "Green"
    }

    if ([int]$cc.CrashDumpEnabled -eq 3) {
        Add-Line "  *** Minidumps only. Change to Kernel dump (2) for better diagnostics ***" "Yellow"
    }
} catch {
    Add-Line "  [ERROR] Could not read CrashControl settings: $_" "Red"
}

Add-Line ""

try {
    $pf = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction Stop
    if ($pf) {
        foreach ($p in $pf) {
            Add-KV "Pagefile Path"   $p.Name
            Add-KV "Initial Size"    "$($p.InitialSize) MB"
            Add-KV "Maximum Size"    "$($p.MaximumSize) MB"
        }
    } else {
        Add-Line "  Pagefile is system-managed (automatic sizing)." "Yellow"
        $pfUsage = Get-WmiObject -Class Win32_PageFileUsage -ErrorAction Stop
        foreach ($pu in $pfUsage) {
            Add-KV "Pagefile (auto)"  $pu.Name
            Add-KV "Allocated Size"   "$($pu.AllocatedBaseSize) MB"
            Add-KV "Current Usage"    "$($pu.CurrentUsage) MB"
            Add-KV "Peak Usage"       "$($pu.PeakUsage) MB"
        }
    }
} catch {
    Add-Line "  [INFO] Could not retrieve pagefile settings." "Yellow"
}

# ---------------------------------------------------------------------------
# Section 10 - System RAM
# ---------------------------------------------------------------------------
Write-Section "10. SYSTEM RAM (for pagefile sizing guidance)"

try {
    $cs    = Get-WmiObject Win32_ComputerSystem
    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
    Add-KV "Total Physical RAM"        "$ramGB GB"
    Add-KV "Recommended pagefile min"  "$ramMB MB  ($ramGB GB)"
    Add-KV "Recommended pagefile max"  "$($ramMB + 300) MB"
    Add-Line ""
    Add-Line "  For kernel dumps: pagefile must be >= RAM size on the system drive." "Cyan"
} catch {
    Add-Line "  [ERROR] Could not retrieve RAM info: $_" "Red"
}

# ---------------------------------------------------------------------------
# Save report
# ---------------------------------------------------------------------------
Write-Section "REPORT COMPLETE"
$Report | Out-File -FilePath $OutputFile -Encoding UTF8
Add-Line "  Report saved to:" "Green"
Add-Line "  $OutputFile"      "Green"
Add-Line ""
Add-Line "  KEY SSD SMART ATTRIBUTES TO CHECK (must be 0 on a healthy drive):"
Add-Line "    Attr   5  Reallocated Sectors Count  -- must be 0" "Cyan"
Add-Line "    Attr 171  SSD Program Fail Count      -- must be 0" "Cyan"
Add-Line "    Attr 172  SSD Erase Fail Count        -- must be 0" "Cyan"
Add-Line "    Attr 187  Uncorrectable Error Count   -- must be 0" "Cyan"
Add-Line "    Attr 197  Current Pending Sectors     -- must be 0" "Cyan"
Add-Line "    Attr 198  Uncorrectable Sectors       -- must be 0" "Cyan"
Add-Line "    Attr 177/231/233  Wear / Life Left    -- higher is better" "Cyan"
Add-Line "    Attr 194  Temperature                 -- must be below 70 C" "Cyan"
Add-Line ""
Add-Line "  Non-zero on attrs 5/171/172/187/197/198 = back up data immediately."
