#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Detects non-standard Windows user profile locations and analyzes profile storage.

.DESCRIPTION
    This script checks if Windows user profiles have been redirected from the default C:\Users location,
    identifies the current profile directory, counts the number of profiles, and calculates their sizes.

.NOTES
    Author: System Administrator
    Requires: Administrator privileges for accurate profile size calculation
#>

# Function to convert bytes to human-readable format
function Convert-Size {
    param([int64]$Size)
    
    if ($Size -gt 1TB) {
        return "{0:N2} TB" -f ($Size / 1TB)
    }
    elseif ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    }
    elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    }
    elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    }
    else {
        return "{0:N0} Bytes" -f $Size
    }
}

# Function to calculate folder size with error handling
function Get-FolderSize {
    param([string]$Path)
    
    $size = 0
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        
        if ($null -eq $size) { $size = 0 }
    }
    catch {
        Write-Verbose "Error calculating size for $Path: $_"
        $size = 0
    }
    
    return $size
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Windows User Profile Location Detector and Analyzer" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Registry path for ProfileList
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$defaultProfilePath = "C:\Users"

try {
    # Check if the registry key exists
    if (Test-Path $regPath) {
        # Get the ProfilesDirectory value
        $profilesDirectory = (Get-ItemProperty -Path $regPath -Name "ProfilesDirectory" -ErrorAction Stop).ProfilesDirectory
        
        Write-Host "Registry Check Results:" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        # Check if it's the default location
        if ($profilesDirectory -eq $defaultProfilePath) {
            Write-Host "✓ Profiles are in the DEFAULT location: " -NoNewline -ForegroundColor Green
            Write-Host $profilesDirectory -ForegroundColor White
        }
        else {
            Write-Host "⚠ PROFILES REDIRECTED TO NON-STANDARD LOCATION!" -ForegroundColor Red
            Write-Host "Current profile directory is: " -NoNewline -ForegroundColor Yellow
            Write-Host "'$profilesDirectory'" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "Profile Analysis:" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        # Check if the profiles directory exists
        if (Test-Path $profilesDirectory) {
            # Get all profile folders (excluding system folders)
            $excludedFolders = @('All Users', 'Default', 'Default User', 'Public', 'desktop.ini')
            $profileFolders = Get-ChildItem -Path $profilesDirectory -Directory -Force -ErrorAction SilentlyContinue | 
                             Where-Object { $_.Name -notin $excludedFolders }
            
            $profileCount = $profileFolders.Count
            
            Write-Host "Profile Directory Path: " -NoNewline -ForegroundColor Gray
            Write-Host $profilesDirectory -ForegroundColor White
            Write-Host "Total User Profiles Found: " -NoNewline -ForegroundColor Gray
            Write-Host $profileCount -ForegroundColor White
            Write-Host ""
            
            if ($profileCount -gt 0) {
                Write-Host "Profile Details:" -ForegroundColor Yellow
                Write-Host "-" * 40 -ForegroundColor Gray
                
                # Create array to store profile information
                $profileInfo = @()
                $totalSize = 0
                
                foreach ($profile in $profileFolders) {
                    Write-Host "Analyzing profile: $($profile.Name)..." -ForegroundColor Gray -NoNewline
                    
                    $profilePath = $profile.FullName
                    $profileSize = Get-FolderSize -Path $profilePath
                    $totalSize += $profileSize
                    
                    # Get last write time
                    $lastModified = $profile.LastWriteTime
                    
                    # Check if profile is currently loaded (active)
                    $isActive = $false
                    $profileSIDs = Get-ChildItem -Path $regPath | Where-Object { $_.PSChildName -match '^S-\d-\d-\d+' }
                    foreach ($sid in $profileSIDs) {
                        $sidProfilePath = (Get-ItemProperty -Path $sid.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                        if ($sidProfilePath -eq $profilePath) {
                            $isActive = $true
                            break
                        }
                    }
                    
                    $profileObj = [PSCustomObject]@{
                        ProfileName = $profile.Name
                        Path = $profilePath
                        SizeBytes = $profileSize
                        SizeFormatted = Convert-Size -Size $profileSize
                        LastModified = $lastModified
                        Status = if ($isActive) { "Active" } else { "Inactive" }
                    }
                    
                    $profileInfo += $profileObj
                    Write-Host " Done" -ForegroundColor Green
                }
                
                Write-Host ""
                
                # Display profile information in a table
                $profileInfo | Sort-Object SizeBytes -Descending | 
                    Format-Table -Property ProfileName, SizeFormatted, LastModified, Status -AutoSize
                
                Write-Host ""
                Write-Host "Summary Statistics:" -ForegroundColor Yellow
                Write-Host "-" * 40 -ForegroundColor Gray
                Write-Host "Total Profiles: " -NoNewline -ForegroundColor Gray
                Write-Host $profileCount -ForegroundColor White
                Write-Host "Total Size of All Profiles: " -NoNewline -ForegroundColor Gray
                Write-Host (Convert-Size -Size $totalSize) -ForegroundColor White
                
                if ($profileCount -gt 0) {
                    $avgSize = $totalSize / $profileCount
                    Write-Host "Average Profile Size: " -NoNewline -ForegroundColor Gray
                    Write-Host (Convert-Size -Size $avgSize) -ForegroundColor White
                }
                
                # Find largest and smallest profiles
                $largest = $profileInfo | Sort-Object SizeBytes -Descending | Select-Object -First 1
                $smallest = $profileInfo | Sort-Object SizeBytes | Select-Object -First 1
                
                Write-Host "Largest Profile: " -NoNewline -ForegroundColor Gray
                Write-Host "$($largest.ProfileName) (" -NoNewline -ForegroundColor White
                Write-Host "$($largest.SizeFormatted)" -NoNewline -ForegroundColor Cyan
                Write-Host ")" -ForegroundColor White
                
                Write-Host "Smallest Profile: " -NoNewline -ForegroundColor Gray
                Write-Host "$($smallest.ProfileName) (" -NoNewline -ForegroundColor White
                Write-Host "$($smallest.SizeFormatted)" -NoNewline -ForegroundColor Cyan
                Write-Host ")" -ForegroundColor White
                
                # Export to CSV if needed
                $exportPath = "$env:TEMP\ProfileAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                $profileInfo | Export-Csv -Path $exportPath -NoTypeInformation
                Write-Host ""
                Write-Host "Detailed report exported to: " -NoNewline -ForegroundColor Gray
                Write-Host $exportPath -ForegroundColor Green
            }
            else {
                Write-Host "No user profiles found in the specified directory." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "ERROR: Profile directory does not exist at path: $profilesDirectory" -ForegroundColor Red
        }
    }
    else {
        Write-Host "ERROR: Registry key not found at: $regPath" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: An error occurred while accessing the registry or file system" -ForegroundColor Red
    Write-Host "Error Details: $_" -ForegroundColor Red
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ""
        Write-Host "NOTE: This script requires Administrator privileges for accurate results." -ForegroundColor Yellow
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Script execution completed." -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
