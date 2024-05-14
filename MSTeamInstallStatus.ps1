# Get all installed Windows Apps
$apps = Get-AppxPackage

# Loop through each app and print its details
foreach ($app in $apps) {
    $appName = $app.Name
    $appPublisher = $app.Publisher
    $appVersion = $app.Version
    $appArchitecture = $app.Architecture
    $appInstallLocation = $app.InstallLocation
    $appPackageFullName = $app.PackageFullName
    
    Write-Host "Name: $appName"
    Write-Host "Publisher: $appPublisher"
    Write-Host "Version: $appVersion"
    Write-Host "Architecture: $appArchitecture"
    Write-Host "Install Location: $appInstallLocation"
    Write-Host "Package Full Name: $appPackageFullName"
    Write-Host ""
}
