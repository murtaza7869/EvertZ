$Apps = Get-AppxPackage -Name "*Teams*" -AllUsers
if($Apps){
    ForEach ($app in $Apps){
   [PSCustomObject]@{
        'Name' = $app.Name
        'Version' = $app.Version}
    }
} else {
   [PSCustomObject]@{
        'Name' = $null
        'Version' = $null
    }
}
