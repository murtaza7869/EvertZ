# Define the path to the XML file
# $xmlFilePath = $Args

# Load the XML file
[xml]$xmlContent = Get-Content $Args

# Print the XML content to the console
$xmlContent.OuterXml
