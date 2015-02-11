Function Remove-rsMof
{
    param( [String] $id, [String] $DestinationPath )
    if( (Test-Path $((Join-Path $DestinationPath $id),'mof' -join '.')) ){
        Remove-Item $((Join-Path $DestinationPath $id),'mof' -join '.') -Force -ErrorAction SilentlyContinue
    }
    if( (Test-Path $((Join-Path $DestinationPath $id),'mof.checksum' -join '.')) ){
        Remove-Item $((Join-Path $DestinationPath $id),'mof.checksum' -join '.') -Force -ErrorAction SilentlyContinue
    }
}
Function Set-rsMof
{
    param(
        [String] $name,
        [String] $id,
        [String] $config,
        [String] $ConfigPath,
        [String] $DestinationPath
    )
    Remove-rsMof -id $id -DestinationPath $DestinationPath
    if(Test-Path $(Join-Path $ConfigPath $config) ) 
    {
        try
        {
            Invoke-Expression "& `'$(Join-Path $ConfigPath $config)`' -Node $name -ObjectGuid $id -DestinationPath `"$DestinationPath`"" -Verbose
        }
        catch 
        {
            Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "Error creating mof for $name using $config `n$($_.Exception.message)"
            Write-Verbose "Error creating mof for $name using $config `n$($_.Exception.message)"
        }
    }
    else 
    {
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
        [String]$PullServerConfig,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    @{
        Name = $Name
        DedicatedKey = $DedicatedKey
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
        [String]$PullServerConfig,
        [String]$DestinationPath,
        [String]$CSVPath,
        [String]$ConfigPath,
        [String]$ConfigHashPath,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    Import-Module rsCommon
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource
   
    $results = @()
    # List All Dedicated Servers
    if(Test-Path $CSVPath)
    {
        $results += Import-Csv -Path $CSVPath | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    else 
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file $CSVPath does not exist."
    }
    $results = ($results | ? rax_dsc_config -ne $PullServerConfig)
   
    # Remove mof & Checksums that do not exist
    $exclusions = $results.id | % { "*",($_,"mof" -join "."),"*" -join '';"*",($_,"mof.checksum" -join "."),"*" -join ''}
    if(Get-ChildItem $DestinationPath -Exclude $exclusions)
    {
        Get-ChildItem $DestinationPath -Exclude $exclusions | Remove-Item -force
    }
    else 
    {
        Get-ChildItem $DestinationPath | Remove-Item -force
    }
   
    # Get Client Configs except for PullServer
    $configs = $results.rax_dsc_config | Sort -Unique
    # If Client Config Updated, Remove Mof
    foreach( $config in $configs )
    {
        if( !(Test-rsHash $(Join-Path $ConfigPath $config) $(Join-Path $ConfigHashPath $($config,'hash' -join '.'))) )
        {
            foreach( $server in $($results | ? rax_dsc_config -eq $config) )
            {
                Remove-rsMof -id $($server.id) -DestinationPath $DestinationPath
            }
            Set-rsHash $(Join-Path $ConfigPath $config) $(Join-Path $ConfigHashPath $($config,'hash' -join '.'))
        }
    }
    # Create Missing
    foreach( $server in $results )
    {
        if( !(Test-Path $((Join-Path $DestinationPath $($server.id)),'mof' -join '.')) -or !(Test-Path $((Join-Path $DestinationPath $($server.id)),'mof.checksum' -join '.')) )
        {
            Set-rsMof -name $($server.name) -id $($server.id) -config $($server.rax_dsc_config) -DestinationPath $DestinationPath -ConfigPath $ConfigPath
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
        [String]$PullServerConfig,
        [String]$DestinationPath,
        [String]$CSVPath,
        [String]$ConfigPath,
        [String]$ConfigHashPath,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    Import-Module rsCommon
    $testresult = $true
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource
    $results = @()
    # List All Dedicated Servers
    if(Test-Path $CSVPath)
    {
        $results += Import-Csv -Path $CSVPath | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    else 
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file path $CSVPath does not exist."
    }
    $results = ($results | ? rax_dsc_config -ne $PullServerConfig)
   
    if($results.id.count -ne (((Get-ChildItem $DestinationPath).count)/2))
    {
        $testresult = $false
    }
   
    $configs = $results.rax_dsc_config | Sort -Unique
    foreach( $config in $configs )
    {
        if( !(Test-rsHash $(Join-Path $ConfigPath $config) $(Join-Path $ConfigHashPath $($config,'hash' -join '.'))) )
        {
            $testresult = $false
        }
    }
    foreach( $server in $results )
    {
        if( !(Test-Path $((Join-Path $DestinationPath $($server.id)),'mof' -join '.')) -or !(Test-Path $((Join-Path $DestinationPath $($server.id)),'mof.checksum' -join '.')) )
        {
            $testresult = $false
        }
    }
    return $testresult
}
Export-ModuleMember -Function *-TargetResource
