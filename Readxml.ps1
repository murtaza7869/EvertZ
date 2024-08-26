# Check if the script was passed an argument
if ($args.Length -eq 0) {
    Write-Host "Usage: .\ReadXmlFile.ps1 <PathToXmlFile>"
    exit
}

# Get the XML file path from the script's argument
$xmlFilePath = $args[0]

# Check if the file exists
if (-Not (Test-Path $xmlFilePath)) {
    Write-Host "File not found: $xmlFilePath"
    exit
}

# Load the XML file
[xml]$xmlContent = Get-Content $xmlFilePath

# Print the XML content to the console
$xmlContent.OuterXml
