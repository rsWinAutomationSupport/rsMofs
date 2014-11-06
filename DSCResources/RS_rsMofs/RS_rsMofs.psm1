﻿Function Get-rsDetailsServers
{
    $catalog = Get-rsServiceCatalog
    $endpoints = ($catalog.access.serviceCatalog | ? name -eq "cloudServersOpenStack").endpoints.publicURL
    foreach( $endpoint in $endpoints )
    {
        $temp = (Invoke-rsRestMethod -Uri $($endpoint,"servers/detail" -join "/") -Method GET -Headers $(Get-rsAuthToken) -ContentType application/json)
        $servers = $servers,$temp
    }
    return ( ($servers.servers | ? {@("Deleted", "Error", "Unknown") -notcontains $_.status}) )
}
Function Test-rsHash
{
    param (
    [String] $file,
    [String] $hash
    )
    if ( !(Test-Path $hash) ){
        return $false
    }
    if( (Get-FileHash $file).hash -eq (Import-Csv $hash).hash){
        return $true
    }
    if( (Get-FileHash $file).hash -eq (Import-Csv $hash)){
        return $true
    }
    else {
        return $false
    }
}
Function Set-rsHash
{
    param (
    [String] $file,
    [String] $hash
    )
    Set-Content -Path $hash -Value (Get-FileHash -Path $file | ConvertTo-Csv)
}
Function Remove-rsMof
{
    param( [String] $id )
    $mofFolder = "C:\Program Files\WindowsPowerShell\DscService\Configuration"
    if( (Test-Path $(($mofFolder,$id -join '\'),'mof' -join '.')) ){
        Remove-Item $(($mofFolder,$id -join '\'),'mof' -join '.') -Force -ErrorAction SilentlyContinue
    }
    if( (Test-Path $(($mofFolder,$id -join '\'),'mof.checksum' -join '.')) ){
        Remove-Item $(($mofFolder,$id -join '\'),'mof.checksum' -join '.') -Force -ErrorAction SilentlyContinue
    }
}
Function Set-rsMof
{
    param(
    [String] $name,
    [String] $id,
    [String] $config
    )
    Remove-rsMof -id $id
    if(Test-Path $("C:\DevOps",$d.mR,$config -join'\') ) {
        try{
            Invoke-Expression "$("C:\DevOps", $d.mR, $config -join '\') -Node $name -ObjectGuid $id -MonitoringID $([guid]::NewGuid()) -MonitoringToken $([guid]::NewGuid())"
        }
        catch {
            Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "Error creating mof for $name using $config `n$($_.Exception.message)"
        }
    }
    else {
        Write-Verbose "$config does not exist"
    }
}
function Get-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$DedicatedKey,
        [String]$CloudKey,
        [String]$PullServerConfig,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    @{
        Name = $Name
        DedicatedKey = $DedicatedKey
        CoudKey = $CloudKey
        PullServerConfig = $PullServerConfig
        Ensure = $Ensure
    } 
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$DedicatedKey,
        [String]$CloudKey,
        [String]$PullServerConfig,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource
    . (Get-rsSecrets)

    $mofFolder = "C:\Program Files\WindowsPowerShell\DscService\Configuration"
    # List All Cloud Servers using Heat metadata
    if($d.ContainsKey("rs_username") -and $d.ContainsKey("rs_apikey") ){
        $cloudresults = Get-rsDetailsServers | ? {$_.metadata -match $CloudKey} | Select -Property name,id -ExpandProperty metadata | Select name,id,@{Name="rax_dsc_config";Expression=$CloudKey}
    }
    # List All Dedicated Servers
    if(Test-Path $("C:\DevOps",$d.mR,"dedicated.csv" -join '\')){
        $dedicatedresults = Import-Csv -Path $("C:\DevOps",$d.mR,"dedicated.csv" -join '\') | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    # Combine results
    $results = @()
    $results += $cloudresults
    $results += $dedicatedresults
    $results = ($results | ? rax_dsc_config -ne $PullServerConfig)

    # Remove mof & Checksums that do not exist
    $exclusions = $results.id | % { "*",($_,"mof" -join "."),"*" -join '';"*",($_,"mof.checksum" -join "."),"*" -join ''}
    if(Get-ChildItem $mofFolder -Exclude $exclusions){
        Get-ChildItem $mofFolder -Exclude $exclusions | Remove-Item -force
    }
    else {
        Get-ChildItem $mofFolder | Remove-Item -force
    }

    # Get Client Configs except for PullServer
    $configs = $results.rax_dsc_config | Sort -Unique
    # If Client Config Updated, Remove Mof
    foreach( $config in $configs )
    {
        if( !(Test-rsHash $("C:\DevOps",$d.mR,$config -join'\') $("C:\DevOps",$($config,'hash' -join '.') -join'\')) )
        {
            foreach( $server in $($results | ? rax_dsc_config -eq $config) ){
                Remove-rsMof -id $($server.id)
            }
            Set-rsHash $("C:\DevOps",$d.mR,$config -join'\') $("C:\DevOps",$($config,'hash' -join '.') -join'\')
        }
    }
    # Create Missing
    foreach( $server in $($results | ? rax_dsc_config -eq $config) ){
        if( !(Test-Path $(($mofFolder,$($server.id) -join '\'),'mof' -join '.')) -or !(Test-Path $(($mofFolder,$($server.id) -join '\'),'mof.checksum' -join '.')) )
        {
            Set-rsMof -name $($server.name) -id $($server.id) -config $config
        }
    }
}

function Test-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$DedicatedKey,
        [String]$CloudKey,
        [String]$PullServerConfig,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    $testresult = $true
    $mofFolder = "C:\Program Files\WindowsPowerShell\DscService\Configuration"
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    $exists = Import-Module rsCommon -ErrorAction SilentlyContinue -PassThru
    if( [string]::IsNullOrEmpty($exists) )
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1003 -Message "rsCommon is not located on this machine"
        Throw "rsCommon is not located on this machine"
    }
    New-rsEventLogSource -logSource $logSource
    . (Get-rsSecrets)
    if($d.ContainsKey("rs_username") -and $d.ContainsKey("rs_apikey") ){
        $cloudresults = Get-rsDetailsServers | ? {$_.metadata -match $CloudKey} | Select -Property name,id -ExpandProperty metadata | Select name,id,@{Name="rax_dsc_config";Expression=$CloudKey}
    }
    if(Test-Path $("C:\DevOps",$d.mR,"dedicated.csv" -join '\')){
        $dedicatedresults = Import-Csv -Path $("C:\DevOps",$d.mR,"dedicated.csv" -join '\') | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    $results = @()
    $results += $cloudresults
    $results += $dedicatedresults
    $results = ($results | ? rax_dsc_config -ne $PullServerConfig)
    
    if($results.id.count -ne (((Get-ChildItem $mofFolder).count)/2)){
        $testresult = $false
    }

    $configs = $results.rax_dsc_config | Sort -Unique
    foreach( $config in $configs )
    {
        if( !(Test-rsHash $("C:\DevOps",$d.mR,$config -join'\') $("C:\DevOps",$($config,'hash' -join '.') -join'\')) )
        {
            $testresult = $false
        }
    }
    foreach( $server in $($results | ? rax_dsc_config -eq $config) ){
        if( !(Test-Path $(($mofFolder,$($server.id) -join '\'),'mof' -join '.')) -or !(Test-Path $(($mofFolder,$($server.id) -join '\'),'mof.checksum' -join '.')) )
        {
            $testresult = $false
        }
    }
    return $testresult
}
Export-ModuleMember -Function *-TargetResource
