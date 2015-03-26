Function TestHash
{
    [CmdletBinding()]
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

function ReadNodeData
{
     [CmdletBinding()]
     param (
          [string]$NodeData
     )

     if(Test-Path $NodeData)
     {
          return (Get-Content $NodeData) -join "`n" | ConvertFrom-Json
     }
     else
     {
          Write-Verbose "The file path $NodeData does not exist."
          Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file path $NodeData does not exist."
     }
}

function RemoveMof
{
    [CmdletBinding()]
    param (
        [String] $uuid,
        [String] $MofPath
    )

    $MofFile = (($MofPath,$uuid -join '\'),'mof' -join '.')
    $MofFileHash = ($MofFile,'checksum' -join '.')
    
    if( Test-Path $MofFile )
    {
        Remove-Item $MofFile -Force -ErrorAction SilentlyContinue
    }
    
    if( Test-Path $MofFileHash )
    {
        Remove-Item $MofFileHash -Force -ErrorAction SilentlyContinue
    }
}

function Get-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$nodeData,
        [string]$mofDestPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration",
        [string]$configPath = "C:\DevOps\DDI_rsConfigs",
        [string]$configHashPath,
        [string]$pullConfig = "rsPullServer.ps1",
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    
    if (!($configHashPath))
    {
        $confHash = $configPath
    }

    @{
         nodeData = $nodeData
         mofDestPath = $mofDestPath
         configPath = $configPath
         configHashPath = $configHashPath
         pullConfig = $pullConfig
     } 
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$nodeData,
        [string]$mofDestPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration",
        [string]$configPath = "C:\DevOps\DDI_rsConfigs",
        [string]$configHashPath,
        [string]$pullConfig = "rsPullServer.ps1",
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )

    Import-Module rsCommon
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource

    # Retreive current node data set
    $allServers = (ReadNodeData -NodeData $nodeData).Nodes

    # Remove mof & checksums that no longer exist in $AllServers
    $exclusions = $allServers.uuid | ForEach-Object { "*",($_,"mof" -join "."),"*" -join '';"*",($_,"mof.checksum" -join "."),"*" -join ''}
    $removalList = Get-ChildItem $mofDestPath -Exclude $exclusions

    if( $removalList )
    {
        Remove-Item -Include $removalList -force
    }
    else 
    {
        Get-ChildItem $mofDestPath | Remove-Item -force
    }
    
    # Check configurations for updates by comparing each config file and its hash
    $configs = ($allServers.dsc_config | Where-Object dsc_config -ne $pullConfig | Sort -Unique)
    
    # Remove mof files if the main DSC client config file has been updated and generate new config checksum
    foreach( $config in $configs )
    {       
        $confFile = Join-Path $configPath $config
        if ($configHashPath)
        {
            $confHash = Join-Path $configHashPath $($config,'checksum' -join '.')
        }
        else
        {
            $confHash = Join-Path $configPath $($config,'checksum' -join '.')
        }

        if( !(TestHash $confFile $confHash) )
        {
            foreach( $server in $($allServers | Where-Object rax_dsc_config -eq $config) )
            {
                RemoveMof -uuid $($server.uuid) -MofPath $mofDestPath
            }

            Set-Content -Path $confHash -Value (Get-FileHash -Path $confFile | ConvertTo-Csv)
        }
    }

    # Generate new or replace outdated mof and checksum files
    foreach( $server in $allServers )
    {
        $mofFile = (($mofDestPath,$server.uuid -join '\'),'mof' -join '.')
        $mofFileHash = ($mofFile,'checksum' -join '.')

        if( !(Test-Path $MofFile) -or !(Test-Path $MofFileHash) )
        {
            RemoveMof -uuid $($server.uuid) -MofPath $mofDestPath
            if( Test-Path $confFile )
            {
                try
                {
                   Invoke-Expression "$($confFile) -Node $($server.NodeName) -Objectuuid $($server.uuid)"
                }
                catch 
                {
                   Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "Error creating mof for $($server.NodeName) using $confFile `n$($_.Exception.message)"
                }
            }
            else 
            {
                Write-Verbose "$confFile was not found. Creation of mof file for $($server.NodeName) has failed."
                Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1003 -Message "$confFile was not found. Creation of mof file for $($server.NodeName) has failed."
            }
        }
    }
}

function Test-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$nodeData,
        [string]$mofDestPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration",
        [string]$configPath = "C:\DevOps\DDI_rsConfigs",
        [string]$configHashPath,
        [string]$pullConfig = "rsPullServer.ps1",
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    
    Import-Module rsCommon
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource
    
    # Retreive current node data
    $allServers = (ReadNodeData -NodeData $nodeData).Nodes
    
    # Check if mof destination file count is equal to the number of nodes in NodeData
    if($allServers.uuid.count -ne (((Get-ChildItem $mofDestPath).count)/2))
    {
        Write-Verbose "Number of nodes in supplied NodeData does not match number of mof or checksum files"
        return $false
    }
    
    # Check configurations for updates by comparing each config file and its hash
    $configs = ($allServers.dsc_config | Where-Object dsc_config -ne $pullConfig | Sort -Unique)
    
    foreach( $config in $configs )
    {
        $confFile = Join-Path $configPath $config
        if ($configHashPath)
        {
            $confHash = Join-Path $configHashPath $($config,'checksum' -join '.')
        }
        else
        {
            $confHash = Join-Path $configPath $($config,'checksum' -join '.')
        }
        

        if( !(TestHash $confFile $confHash))
        {
             Write-Verbose "$confFile hash check failed"
             return $false
        }
    }
    
    # Check if each node has a mof and checksum present
    # Then ensure that mof file is valid by comparing with its checksum
    foreach($node in $allServers)
    {
        $nodeMofFile = ((Join-Path $mofDestPath $($node.uuid)),'mof' -join '.')
        $nodeMofHash = ((Join-Path $mofDestPath $($node.uuid)),'mof.checksum' -join '.')

        if( !(Test-Path $nodeMofFile) -or !(Test-Path $nodeMofHash))
        {
            Write-Verbose "$nodeMofFile or its hash file not found"
            return $false
        }

        if( !(TestHash -file $nodeMofFile -hash $nodeMofHash))
        {
            Write-Verbose "$nodeMofFile hash validaton failed"
            return $false
        }
    }
    return $true
}

Export-ModuleMember -Function *-TargetResource