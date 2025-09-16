#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Detects non-standard Windows user profile locations and analyzes profile storage.
    Simple output version for deployment tools.

.DESCRIPTION
    Checks if Windows user profiles have been redirected from default C:\Users location 
    and provides profile statistics with minimal output.

.NOTES
    Author: System Administrator
    Version: 3.0 - Simple output without exit codes
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
        # Silent error handling
        $size = 0
    }
    
    return $size
}

# Initialize variables
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$defaultProfilePath = "C:\Users"

try {
    # Check if the registry key exists
    if (-not (Test-Path $regPath)) {
        Write-Host "ERROR: Registry key not found at $regPath"
        return
    }
    
    # Get the ProfilesDirectory value
    $profilesDirectory = (Get-ItemProperty -Path $regPath -Name "ProfilesDirectory" -ErrorAction Stop).ProfilesDirectory
    
    # Check if it's the default location
    if ($profilesDirectory -eq $defaultProfilePath) {
        Write-Host "Profile location: DEFAULT ($profilesDirectory)"
    }
    else {
        Write-Host "Profile location: CUSTOM"
        Write-Host "Current profile directory is '$profilesDirectory'"
    }
    
    # Check if the profiles directory exists
    if (-not (Test-Path $profilesDirectory)) {
        Write-Host "ERROR: Profile directory does not exist at $profilesDirectory"
        return
    }
    
    # Get all profile folders (excluding system folders)
    $excludedFolders = @('All Users', 'Default', 'Default User', 'Public', 'desktop.ini')
    $profileFolders = Get-ChildItem -Path $profilesDirectory -Directory -Force -ErrorAction SilentlyContinue | 
                     Where-Object { $_.Name -notin $excludedFolders }
    
    $profileCount = $profileFolders.Count
    
    if ($profileCount -eq 0) {
        Write-Host "No user profiles found in $profilesDirectory"
        return
    }
    
    Write-Host "Total profiles: $profileCount"
    
    # Calculate sizes
    $totalSize = 0
    $profileList = @()
    
    foreach ($profile in $profileFolders) {
        $profileSize = Get-FolderSize -Path $profile.FullName
        $totalSize += $profileSize
        
        $profileList += [PSCustomObject]@{
            Name = $profile.Name
            Size = Convert-Size -Size $profileSize
            SizeBytes = $profileSize
        }
    }
    
    # Output total size
    Write-Host "Total size: $(Convert-Size -Size $totalSize)"
    
    # Output each profile
    Write-Host ""
    Write-Host "Profile details:"
    foreach ($profile in $profileList | Sort-Object SizeBytes -Descending) {
        Write-Host "  $($profile.Name): $($profile.Size)"
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}
