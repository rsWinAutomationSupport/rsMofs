Function TestHash
{
  param (
    [String] $file,
    [String] $hash
  )
    
  if ( !(Test-Path $hash) -or !(Test-Path $file))
  {
    return $false
  }
       
  if( (Get-FileHash $file).hash -eq (Get-Content $hash))
  {
    return $true
  }
  else
  {
    return $false
  }
}

function ReadNodeData
{
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
    #Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file path $NodeData does not exist."
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
    $configHashPath = $configPath
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

  #Import-Module rsCommon
  #$logsource = "rsMofs"
  #$logsource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
  #New-rsEventLogSource -logSource $logSource

  # Retreive current node data set
  $allServers = (ReadNodeData -NodeData $nodeData).Nodes
  
  # Remove mof & checksums that no longer exist in $AllServers
  #
  # Create an exclusions list with correct format
  #$exclusions = $allServers.uuid | ForEach-Object { "*",($_,"mof" -join "."),"*" -join '';"*",($_,"mof.checksum" -join "."),"*" -join ''  }
  $exclusions = $allServers.uuid | ForEach-Object { $_,"mof" -join ".";$_,"mof.checksum" -join "."}

  $removalList = Get-ChildItem $mofDestPath -Exclude $exclusions

  if( $removalList )
  {
    Remove-Item -Path $removalList.FullName -Force
  }
  
    
  # Check configurations for updates by comparing each config file and its hash
  $configs = ($allServers.dsc_config | Where-Object {$_.dsc_config -ne $pullConfig} | Sort -Unique)
    
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
        
    if (Test-Path $confFile)
    {
      if( !(TestHash -file $confFile -hash $confHash) )
      {
        Write-Verbose "$confFile has been modified - regenerating affected mofs..."
        foreach( $server in $($allServers | Where-Object dsc_config -eq $config) )
        {
          Write-Verbose "Removing outdated mof file for $($server.nodeName) - $($server.uuid)"
                    
          RemoveMof -uuid $($server.uuid) -MofPath $mofDestPath
        }

        Write-Verbose "Generating new checksum for $confFile"
        Set-Content -Path $confHash -Value (Get-FileHash -Path $confFile).hash
      }
    }
    else
    {
      # A bit of checksum house keeping 
      if ( Test-Path $confHash )
      {
        Write-Verbose "Removing $confHash"
        Remove-Item -Path $confHash -Force
      }
    }
  }

  # Generate new or replace outdated mof and checksum files
  foreach( $server in $allServers )
  {
    $srvname = $server.NodeName
    $confFile = Join-Path $configPath $server.dsc_config
    $mofFile = (($mofDestPath,$server.uuid -join '\'),'mof' -join '.')
    $mofFileHash = ($mofFile,'checksum' -join '.')

    if (Test-Path $confFile)
    {
      if( !(Test-Path $MofFile) -or !(Test-Path $MofFileHash) -or !(TestHash -file $mofFile -hash $mofFileHash))
      {
                
        try
        {
          Write-Verbose "Recreating mofs for $srvname"
          RemoveMof -uuid $($server.uuid) -MofPath $mofDestPath
                    
          Write-Verbose "Calling $confFile `n $server.NodeName `n $server.uuid"
                    
          Invoke-Expression "$($confFile) -Node $($server.NodeName) -Objectuuid $($server.uuid)"
        }
        catch 
        {
          Write-Verbose "Error creating mof for $($server.NodeName) using $confFile `n$($_.Exception.message)"
          #Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "Error creating mof for $($server.NodeName) using $confFile `n$($_.Exception.message)"
        }
      }
    }
    else
    {
      # Remove left-over mofs for any servers with missing dsc configuration
      Write-Verbose "WARNING: $srvname dsc configuration file not found - $confFile"
      RemoveMof -uuid $($server.uuid) -MofPath $mofDestPath
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
    
  #Import-Module rsCommon
  #$logsource = 'rsMofs'
  #$logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
  #New-rsEventLogSource -logSource $logSource
    
  # Retreive current node data
  $allServers = (ReadNodeData -NodeData $nodeData).Nodes
  $exclusions = $allServers.uuid | ForEach-Object { $_,"mof" -join ".";$_,"mof.checksum" -join "."}
  $removalList = Get-ChildItem $mofDestPath -Exclude $exclusions
  
  # Check configurations for updates by comparing each config file and its hash
  $configs = ($allServers.dsc_config | Where-Object dsc_config -ne $pullConfig | Sort -Unique)
    
  foreach( $config in $configs )
  {
    $confFile = Join-Path $configPath $config
        
    if (Test-Path $confFile)
    {
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
    else
    {
      Write-Verbose "WARNING: A configuration file referenced in $nodeData was not found - $confFile"
    }
  }
    
  # Check if each node has a mof and checksum present
  foreach($server in $allServers)
  {
    $srvname = $server.NodeName
    $confFile = Join-Path $configPath $($server.dsc_config)
    $serverMofFile = ((Join-Path $mofDestPath $($server.uuid)),'mof' -join '.')
    $serverMofHash = ($serverMofFile,'checksum' -join '.')

    # Skip servers that do not have a valid config defined
    if (Test-Path $confFile)
    {
      if( !(Test-Path $serverMofFile) -or !(Test-Path $serverMofHash))
      {
        Write-Verbose "$serverMofFile or its hash file not found"
        return $false
      }

      if( !(TestHash -file $serverMofFile -hash $serverMofHash))
      {
        Write-Verbose "$serverMofFile hash validaton failed"
        return $false
      }
    }
    else
    {
      Write-Verbose "WARNING: $srvname is missing its configuration file"
            
      # Ensure that any invalid mofs are removed
      if ( (Test-path $serverMofFile) -or (Test-Path $serverMofHash) -or ($removalList))
      {
        return $false
      }
    }
  }
  
  if($removalList) 
  {
    return $false
  }

  return $true
}

Export-ModuleMember -Function *-TargetResource