# Define the URL for downloading the latest version of Microsoft Teams Windows App
$teamsDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"

# Define the path to download the installer
md C:\temp
$installerPath = "C:\Temp\TeamsBootstrapInstaller.exe"

# Function to check if Microsoft Teams Windows App is installed
function CheckIfTeamsInstalled {
    $teamsInstalled = Get-AppxPackage | Where-Object { $_.Name -eq "MSTeams" }
    return [bool]$teamsInstalled
}

# Function to get the installed version of Microsoft Teams Windows App
function GetTeamsInstalledVersion {
    $teamsInstalled = Get-AppxPackage | Where-Object { $_.Name -eq "MSTeams" }
    if ($teamsInstalled) {
        return $teamsInstalled.Version
    } else {
        return $null
    }
}

# Function to install or update Microsoft Teams Windows App
function InstallOrUpdateTeams {
    # Check if Microsoft Teams Windows App is already installed
    $installedVersion = GetTeamsInstalledVersion
    if ($installedVersion) {
        Write-Host "Microsoft Teams Windows App version $installedVersion is already installed."
    } else {
        Write-Host "Microsoft Teams Windows App is not installed. Downloading and installing..."
        try {
            # Download the latest version of Microsoft Teams Windows App
            Invoke-WebRequest -Uri $teamsDownloadUrl -OutFile $installerPath

            # Install Microsoft Teams Windows App silently
            Start-Process -FilePath $installerPath -ArgumentList "-p" -Wait

            # Clean up the installer
            Remove-Item $installerPath

            Write-Host "Microsoft Teams Windows App has been installed successfully."
        } catch {
            Write-Host "Failed to install Microsoft Teams Windows App. Error: $_"
        }
    }
}

# Main script logic
$teamsInstalled = CheckIfTeamsInstalled
if ($teamsInstalled) {
    # Check if installed version is outdated
    $installedVersion = GetTeamsInstalledVersion
    if ($installedVersion -ne "24091.214.2846.1452") { # Change this version number to the latest version
        Write-Host "Microsoft Teams Windows App is installed but outdated (Version: $installedVersion). Updating..."
        InstallOrUpdateTeams
    } else {
        Write-Host "Microsoft Teams Windows App is already up-to-date."
    }
} else {
    # Teams Windows App not installed, so install it
    InstallOrUpdateTeams
}
