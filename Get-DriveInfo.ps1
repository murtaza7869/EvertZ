#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive SSD / Physical Drive Information Collector
    For use in diagnosing disk health issues on Windows 11
.NOTES
    Run as Administrator in PowerShell 5.1 or PowerShell 7+
    Output is saved to the same folder the script is run from
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
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Title"           -ForegroundColor Cyan
    Write-Host $line                -ForegroundColor Cyan
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

# ─── Header ──────────────────────────────────────────────────────────────────
$Report.Add("DRIVE DIAGNOSTIC REPORT")
$Report.Add("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Report.Add("Hostname  : $(hostname)")
$Report.Add("User      : $env:USERNAME")
Write-Host "`nDRIVE DIAGNOSTIC REPORT — $(hostname)" -ForegroundColor Yellow
Write-Host "Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# ─── Section 1: Physical Disk Summary ────────────────────────────────────────
Write-Section "1. PHYSICAL DISK SUMMARY"

try {
    $physDisks = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($disk in $physDisks) {
        Add-Line ""
        Add-KV "Disk Index"        $disk.DeviceId
        Add-KV "Friendly Name"     $disk.FriendlyName
        Add-KV "Serial Number"     $disk.SerialNumber
        Add-KV "Media Type"        $disk.MediaType           # SSD / HDD / Unspecified
        Add-KV "Bus Type"          $disk.BusType             # NVMe / SATA / USB
        Add-KV "Size"              ("{0:N2} GB" -f ($disk.Size / 1GB))
        Add-KV "Health Status"     $disk.HealthStatus        # Healthy / Warning / Unhealthy
        Add-KV "Operational Status" $disk.OperationalStatus
        Add-KV "Spindle Speed"     $(if ($disk.SpindleSpeed -eq 0) { "N/A (SSD)" } else { "$($disk.SpindleSpeed) RPM" })
        Add-KV "Firmware Version"  $disk.FirmwareVersion

        # Colour-code health
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

# ─── Section 2: Disk / Partition Layout ──────────────────────────────────────
Write-Section "2. DISK & PARTITION LAYOUT"

try {
    $disks = Get-Disk | Sort-Object Number
    foreach ($d in $disks) {
        Add-Line ""
        Add-KV "Disk Number"       $d.Number
        Add-KV "Friendly Name"     $d.FriendlyName
        Add-KV "Partition Style"   $d.PartitionStyle        # GPT / MBR
        Add-KV "Total Size"        ("{0:N2} GB" -f ($d.Size / 1GB))
        Add-KV "Allocated Size"    ("{0:N2} GB" -f ($d.AllocatedSize / 1GB))
        Add-KV "Boot Disk"         $d.IsBoot
        Add-KV "System Disk"       $d.IsSystem
        Add-KV "Readonly"          $d.IsReadOnly

        $partitions = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
        foreach ($p in $partitions) {
            $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
            $label  = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(no label)" }
            $letter = if ($p.DriveLetter)       { "$($p.DriveLetter):" } else { "(no letter)" }
            $fs     = if ($vol.FileSystem)      { $vol.FileSystem }      else { "RAW/Unknown" }
            $free   = if ($vol.SizeRemaining)   { "{0:N2} GB free" -f ($vol.SizeRemaining / 1GB) } else { "N/A" }
            Add-Line ("    Partition {0}  {1}  {2}  {3}  FS={4}  {5}" -f `
                $p.PartitionNumber, $letter, $label,
                ("{0:N2} GB" -f ($p.Size / 1GB)), $fs, $free)
        }
    }
} catch {
    Add-Line "  [ERROR] Could not retrieve disk layout: $_" "Red"
}

# ─── Section 3: SMART via WMI (SATA/NVMe) ────────────────────────────────────
Write-Section "3. SMART STATUS (WMI)"

try {
    $smartStatus = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
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
    Add-Line "  [INFO] MSStorageDriver_FailurePredictStatus not available (common on NVMe)" "Yellow"
    Add-Line "         Use CrystalDiskInfo or manufacturer tool for NVMe SMART data." "Yellow"
}

# ─── Section 4: SMART Raw Data ───────────────────────────────────────────────
Write-Section "4. SMART RAW ATTRIBUTE DATA (WMI)"

try {
    $smartData = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictData -ErrorAction Stop
    foreach ($sd in $smartData) {
        Add-KV "Instance" $sd.InstanceName
        # Raw SMART data is 512 bytes; each attribute is 12 bytes starting at offset 2
        $raw = $sd.VendorSpecific
        if ($raw -and $raw.Count -ge 12) {
            Add-Line "  Attr# Name                            Flags  Value  Worst  Raw"
            Add-Line "  ----- ------------------------------- -----  -----  -----  ---"
            $knownAttrs = @{
                1   = "Read Error Rate"
                3   = "Spin-Up Time"
                4   = "Start/Stop Count"
                5   = "Reallocated Sectors Count"    # KEY: >0 = bad blocks
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
                169 = "Remaining Life Percentage"
                171 = "SSD Program Fail Count"       # KEY
                172 = "SSD Erase Fail Count"         # KEY
                173 = "SSD Wear Level Count"
                174 = "Unexpected Power Loss"
                175 = "Program Fail Count (Chip)"
                176 = "Erase Fail Count (Chip)"
                177 = "Wear Leveling Count"           # KEY: SSD health %
                179 = "Used Reserved Block Count"
                180 = "Unused Reserved Block Count"
                181 = "Program Fail Count (Total)"
                182 = "Erase Fail Count (Total)"
                183 = "Runtime Bad Block"
                184 = "End-to-End Error"
                187 = "Uncorrectable Error Count"     # KEY: must be 0
                188 = "Command Timeout"
                189 = "High Fly Writes"
                190 = "Airflow Temperature"
                191 = "G-Sense Error Rate"
                192 = "Power-off Retract Count"
                193 = "Load/Unload Cycle Count"
                194 = "Temperature"                   # KEY
                196 = "Reallocation Event Count"
                197 = "Current Pending Sector Count"  # KEY: must be 0
                198 = "Uncorrectable Sector Count"    # KEY: must be 0
                199 = "UltraDMA CRC Error Count"
                200 = "Write Error Rate"
                201 = "Soft Read Error Rate"
                230 = "Drive Life Protection Status"
                231 = "SSD Life Left"                 # KEY
                232 = "Endurance Remaining"
                233 = "Media Wearout Indicator"       # KEY
                234 = "Average Erase Count"
                235 = "Good Block Count"
                240 = "Head Flying Hours"
                241 = "Total LBAs Written"            # Total TB written
                242 = "Total LBAs Read"
                246 = "Total Host Sector Writes"
                247 = "Host Program Page Count"
                248 = "Background Program Page Count"
                250 = "Read Error Retry Rate"
                251 = "Minimum Spares Remaining"
                252 = "Newly Added Bad Flash Block"
                254 = "Free Fall Protection"
            }
            $criticalAttrs = @(5, 171, 172, 187, 197, 198)

            for ($i = 2; $i -lt [Math]::Min($raw.Count, 362); $i += 12) {
                $attrId = $raw[$i]
                if ($attrId -eq 0) { continue }
                $flags  = ($raw[$i+1]) -bor ($raw[$i+2] -shl 8)
                $value  = $raw[$i+3]
                $worst  = $raw[$i+4]
                # Raw value is 6 bytes little-endian
                $rawVal = [long]$raw[$i+5] `
                    -bor ([long]$raw[$i+6] -shl 8)  `
                    -bor ([long]$raw[$i+7] -shl 16) `
                    -bor ([long]$raw[$i+8] -shl 24) `
                    -bor ([long]$raw[$i+9] -shl 32) `
                    -bor ([long]$raw[$i+10] -shl 40)

                $name   = if ($knownAttrs.ContainsKey([int]$attrId)) { $knownAttrs[[int]$attrId] } else { "Attr $attrId" }
                $line   = "  {0,5}  {1,-31} 0x{2:X4}  {3,5}  {4,5}  {5}" -f $attrId, $name, $flags, $value, $worst, $rawVal

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
    Add-Line "  [INFO] SMART raw data not available via WMI (typical for NVMe drives)" "Yellow"
    Add-Line "         Run CrystalDiskInfo for NVMe SMART attributes." "Yellow"
}

# ─── Section 5: NVMe-specific via StorageSubsystem ───────────────────────────
Write-Section "5. STORAGE SUBSYSTEM & NVMe HEALTH"

try {
    $subsystems = Get-StorageSubSystem -ErrorAction Stop
    foreach ($sub in $subsystems) {
        Add-KV "Subsystem"         $sub.FriendlyName
        Add-KV "Health Status"     $sub.HealthStatus
        Add-KV "Operational Status" $sub.OperationalStatus
        Add-KV "Description"       $sub.Description
        Add-Line ""
    }
} catch {
    Add-Line "  [INFO] StorageSubSystem not available on this configuration" "Yellow"
}

# NVMe error log via WMI
try {
    $nvmeDevs = Get-WmiObject -Namespace root\wmi -Class NVMe_Device_Self_Test -ErrorAction Stop
    Add-Line "  NVMe Self-Test devices found: $($nvmeDevs.Count)"
} catch {
    Add-Line "  [INFO] NVMe WMI self-test class not present — use manufacturer tool" "Yellow"
}

# ─── Section 6: Volume Health & Free Space ───────────────────────────────────
Write-Section "6. VOLUME HEALTH & FREE SPACE"

try {
    $vols = Get-Volume | Where-Object { $_.DriveType -ne "CD-ROM" -and $_.DriveLetter } | Sort-Object DriveLetter
    foreach ($v in $vols) {
        $pctFree = if ($v.Size -gt 0) { [math]::Round(($v.SizeRemaining / $v.Size) * 100, 1) } else { 0 }
        $color   = if ($pctFree -lt 10) { "Red" } elseif ($pctFree -lt 20) { "Yellow" } else { "White" }
        Add-Line ""
        Add-KV "Drive Letter"      "$($v.DriveLetter):"
        Add-KV "Label"             $v.FileSystemLabel
        Add-KV "File System"       $v.FileSystem
        Add-KV "Drive Type"        $v.DriveType
        Add-KV "Total Size"        ("{0:N2} GB" -f ($v.Size / 1GB))
        Add-KV "Free Space"        ("{0:N2} GB  ({1}%)" -f ($v.SizeRemaining / 1GB), $pctFree) $color
        Add-KV "Health Status"     $v.HealthStatus
    }
} catch {
    Add-Line "  [ERROR] Could not retrieve volume info: $_" "Red"
}

# ─── Section 7: Disk Error Events (System Log) ───────────────────────────────
Write-Section "7. DISK / STORAGE ERROR EVENTS (last 7 days)"

try {
    $since = (Get-Date).AddDays(-7)
    $diskEvents = Get-WinEvent -LogName System -ErrorAction Stop | Where-Object {
        $_.TimeCreated -ge $since -and
        $_.LevelDisplayName -in @("Error","Critical","Warning") -and
        $_.ProviderName -match "disk|volmgr|stornvme|storahci|ntfs|fastfat|partmgr|nvmedisk"
    } | Sort-Object TimeCreated -Descending | Select-Object -First 50

    if ($diskEvents) {
        foreach ($ev in $diskEvents) {
            $line = "[{0}] ID={1,-6} Source={2,-25} {3}" -f `
                $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"),
                $ev.Id,
                $ev.ProviderName,
                ($ev.Message -split "`n")[0].Trim()
            $col = if ($ev.LevelDisplayName -eq "Error" -or $ev.LevelDisplayName -eq "Critical") { "Red" } else { "Yellow" }
            $Report.Add("  " + $line)
            Write-Host ("  " + $line) -ForegroundColor $col
        }
    } else {
        Add-Line "  No disk/storage errors in the last 7 days." "Green"
    }
} catch {
    Add-Line "  [ERROR] Could not query event log: $_" "Red"
}

# ─── Section 8: chkdsk Scheduled / Last Run ──────────────────────────────────
Write-Section "8. CHKDSK STATUS"

try {
    # Check if chkdsk is scheduled for next boot
    $chkdskReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -ErrorAction Stop
    $bootExec   = $chkdskReg.BootExecute -join " "
    Add-KV "BootExecute entry"  $bootExec
    if ($bootExec -match "chkdsk") {
        Add-Line "  *** chkdsk IS scheduled to run on next reboot ***" "Yellow"
    } else {
        Add-Line "  chkdsk is NOT currently scheduled." "Green"
    }
} catch {
    Add-Line "  [ERROR] Could not read BootExecute registry key: $_" "Red"
}

# Last chkdsk result from event log
try {
    $chkdskEvent = Get-WinEvent -LogName Application -ErrorAction Stop |
        Where-Object { $_.Id -eq 26212 -and $_.ProviderName -eq "Microsoft-Windows-Wininit" } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 1

    if ($chkdskEvent) {
        Add-Line ""
        Add-KV "Last chkdsk run"  $chkdskEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        Add-Line "  Result (first 500 chars):"
        Add-Line ("  " + $chkdskEvent.Message.Substring(0, [Math]::Min(500, $chkdskEvent.Message.Length)))
    } else {
        Add-Line "  No previous chkdsk result found in Application log (EventID 26212)." "Yellow"
    }
} catch {
    Add-Line "  [INFO] Could not retrieve chkdsk history from event log." "Yellow"
}

# ─── Section 9: Pagefile & CrashControl (relevant to dump investigation) ─────
Write-Section "9. PAGEFILE & CRASHCONTROL SETTINGS"

try {
    $cc = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction Stop
    $dumpTypes = @{ 0="Disabled"; 1="Complete"; 2="Kernel"; 3="Small (Minidump)"; 7="Automatic" }
    Add-KV "CrashDumpEnabled"    "$($cc.CrashDumpEnabled) — $($dumpTypes[[int]$cc.CrashDumpEnabled])"
    Add-KV "DumpFile"            $cc.DumpFile
    Add-KV "MinidumpDir"         $cc.MinidumpDir
    Add-KV "AutoReboot"          $cc.AutoReboot
    Add-KV "AlwaysKeepMemoryDump" $cc.AlwaysKeepMemoryDump
    Add-KV "PagefileTooSmall"    $(if ($cc.PagefileTooSmall -and $cc.PagefileTooSmall -ne 0) { "*** YES — MEMORY.DMP WILL NOT BE WRITTEN ***" } else { "No" })

    if ($cc.PagefileTooSmall -and $cc.PagefileTooSmall -ne 0) {
        Add-Line "  *** ACTION REQUIRED: Increase pagefile to at least RAM size for full dumps ***" "Red"
    }
    if ($cc.CrashDumpEnabled -eq 3) {
        Add-Line "  *** Only minidumps configured — change to Kernel (2) for better diagnostics ***" "Yellow"
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
        Add-Line "  Pagefile is system-managed (automatic sizing)" "Yellow"
        $pfUsage = Get-WmiObject -Class Win32_PageFileUsage -ErrorAction Stop
        foreach ($pu in $pfUsage) {
            Add-KV "Pagefile (auto)"   $pu.Name
            Add-KV "Allocated Size"    "$($pu.AllocatedBaseSize) MB"
            Add-KV "Current Usage"     "$($pu.CurrentUsage) MB"
            Add-KV "Peak Usage"        "$($pu.PeakUsage) MB"
        }
    }
} catch {
    Add-Line "  [INFO] Could not retrieve pagefile settings" "Yellow"
}

# ─── Section 10: RAM size (for pagefile sizing guidance) ─────────────────────
Write-Section "10. SYSTEM RAM (for pagefile sizing)"

try {
    $cs   = Get-WmiObject Win32_ComputerSystem
    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    Add-KV "Total Physical RAM"  "$ramGB GB"
    Add-KV "Recommended pagefile (min)" "$([math]::Round($ramGB * 1024)) MB  ($ramGB GB)"
    Add-KV "Recommended pagefile (max)" "$([math]::Round($ramGB * 1024 + 300)) MB"
    Add-Line ""
    Add-Line "  To capture kernel dumps: pagefile must be >= RAM size on the system drive." "Cyan"
} catch {
    Add-Line "  [ERROR] Could not retrieve RAM info: $_" "Red"
}

# ─── Save Report ─────────────────────────────────────────────────────────────
Write-Section "REPORT SAVED"
$Report | Out-File -FilePath $OutputFile -Encoding UTF8
Add-Line "  Report saved to: $OutputFile" "Green"
Add-Line ""
Add-Line "  KEY ATTRIBUTES TO CHECK FOR SSD HEALTH:"
Add-Line "    Attr 5  (Reallocated Sectors)   — must be 0" "Cyan"
Add-Line "    Attr 187 (Uncorrectable Errors)  — must be 0" "Cyan"
Add-Line "    Attr 197 (Pending Sectors)       — must be 0" "Cyan"
Add-Line "    Attr 198 (Uncorrectable Sectors) — must be 0" "Cyan"
Add-Line "    Attr 177/231/233 (Wear/Life)     — higher is better" "Cyan"
Add-Line "    Attr 194 (Temperature)           — must be below 70C" "Cyan"
Add-Line ""
Add-Line "  If any KEY attributes show non-zero values, back up data immediately."
