# Define the package full name for Microsoft Teams
$teamsPackageFullName = "MSTeams"

# Check if Microsoft Teams is installed from the Windows Store
$teamsInstalled = Get-AppxPackage | Where-Object { $_.Name -eq $teamsPackageFullName }

# Check if Microsoft Teams is installed
if ($teamsInstalled) {
    Write-Host "Microsoft Teams is installed."
} else {
    # Define the URL for downloading the latest version of Microsoft Teams
    $teamsDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"

    # Define the path to download the installer
    md c:\TeamsDownload
    $installerPath = "c:\TeamsDownload\TeamsBootstrap.exe"

    # Download the latest version of Microsoft Teams
    Invoke-WebRequest -Uri $teamsDownloadUrl -OutFile $installerPath

    # Install Microsoft Teams silently
    Start-Process -FilePath $installerPath -ArgumentList "-p" -Wait

    # Clean up the installer
    Remove-Item $installerPath

    Write-Host "Microsoft Teams has been installed."
}
