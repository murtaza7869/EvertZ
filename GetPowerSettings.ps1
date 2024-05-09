# Get the active power plan
$powerPlan = (Get-CimInstance -Namespace root\cimv2\power -Class Win32_PowerPlan | Where-Object { $_.IsActive }).ElementName

# Retrieve the power settings
$sleepSetting = (Get-WmiObject -Namespace root\cimv2\power -Class Win32_PowerSettingDataIndex | Where-Object { $_.InstanceID -like "*SUB_SLEEP*" }).SettingValue
$hibernateSetting = (Get-WmiObject -Namespace root\cimv2\power -Class Win32_PowerSettingDataIndex | Where-Object { $_.InstanceID -like "*SUB_SLEEP*" }).SettingValue
$standbySetting = (Get-WmiObject -Namespace root\cimv2\power -Class Win32_PowerSettingDataIndex | Where-Object { $_.InstanceID -like "*SUB_SLEEP*" }).SettingValue

# Format the settings
$formattedOutput = @"
Sleep Setting: $sleepSetting minutes
Hibernate Setting: $hibernateSetting minutes
Standby Setting: $standbySetting minutes
"@

# Output the formatted settings
Write-Output $formattedOutput
