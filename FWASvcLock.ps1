# 1. Define the Service Name
$ServiceName = "FWASvc"

# 2. Get the current SDDL of the service
$currentSDDL = sc.exe sdshow $ServiceName

# 3. Define the "Deny Stop" string for Built-in Administrators (BA)
# D: Deny
# (D;;RPWP;;;BA) 
# RP = Service Stop
# WP = Service Write (prevents changing config/disabling)
# BA = Built-in Administrators
$denyAdminStop = "(D;;RPWP;;;BA)"

# 4. Check if the deny rule is already there to avoid duplicates
if ($currentSDDL -notlike "*$denyAdminStop*") {
    # Insert the Deny rule at the beginning of the DACL (D:)
    $newSDDL = $currentSDDL -replace "D:", "D:$denyAdminStop"
    
    # 5. Apply the new Security Descriptor
    sc.exe sdset $ServiceName $newSDDL
    
    Write-Host "Success: Local Admins are now restricted from stopping $ServiceName." -ForegroundColor Green
} else {
    Write-Host "Protection is already applied to $ServiceName." -ForegroundColor Yellow
}
