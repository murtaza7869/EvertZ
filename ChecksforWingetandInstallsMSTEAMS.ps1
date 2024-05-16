# Function to check if Winget is installed
function Check-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Output "Winget is already installed."
    } else {
        Write-Output "Winget is not installed. Please install Winget v1.7 or higher from https://github.com/microsoft/winget-cli/releases"
        exit 1
    }
}

# Function to update Winget
function Update-Winget {
    try {
        winget upgrade --id Microsoft.Winget.Client --accept-source-agreements --accept-package-agreements
        Write-Output "Winget has been updated."
    } catch {
        Write-Output "Failed to update Winget."
        exit 1
    }
}

# Function to install applications using Winget
function Install-Apps {
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $Apps
    )

    foreach ($App in $Apps) {
        try {
            winget install --id $App --silent --accept-source-agreements --accept-package-agreements
            Write-Output "$App has been installed."
        } catch {
            Write-Output "Failed to install $App."
        }
    }
}

# Check if Winget is installed
Check-Winget

# Update Winget to the latest version
Update-Winget

# List of applications to install
$appsToInstall = @(
        "Microsoft.Teams"   #MSTEAMS
)

# Install applications
Install-Apps -Apps $appsToInstall
