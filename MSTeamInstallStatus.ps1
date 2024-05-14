# Define the package full name for Microsoft Teams
$teamsPackageFullName = "MSTeams"

# Check if Microsoft Teams is installed from the Windows Store
$teamsInstalled = Get-AppxPackage | Where-Object { $_.Name -eq $teamsPackageFullName }

# Check if Microsoft Teams is installed
if ($teamsInstalled) {
    Write-Host "Microsoft Teams is installed."
} else {
    Write-Host "Microsoft Teams is not installed."
}
