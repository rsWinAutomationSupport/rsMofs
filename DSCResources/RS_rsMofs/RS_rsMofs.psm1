Function Remove-rsMof
{
   param( [String] $id, [String] $DestinationPath )
   if( (Test-Path $(($DestinationPath,$id -join '\'),'mof' -join '.')) ){
      Remove-Item $(($DestinationPath,$id -join '\'),'mof' -join '.') -Force -ErrorAction SilentlyContinue
   }
   if( (Test-Path $(($DestinationPath,$id -join '\'),'mof.checksum' -join '.')) ){
      Remove-Item $(($DestinationPath,$id -join '\'),'mof.checksum' -join '.') -Force -ErrorAction SilentlyContinue
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
   if(Test-Path $($ConfigPath,$config -join'\') ) {
      try{
         Invoke-Expression "& `'$($ConfigPath, $config -join '\')`' -Node $name -ObjectGuid $id -DestinationPath `"$DestinationPath`"" -Verbose
      }
      catch {
         Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "Error creating mof for $name using $config `n$($_.Exception.message)"
         Write-Verbose "Error creating mof for $name using $config `n$($_.Exception.message)"
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
    if(Test-Path $CSVPath){
        $results += Import-Csv -Path $CSVPath | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    else {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file $CSVPath does not exist."
    }
   $results = ($results | ? rax_dsc_config -ne $PullServerConfig)
   
   # Remove mof & Checksums that do not exist
   $exclusions = $results.id | % { "*",($_,"mof" -join "."),"*" -join '';"*",($_,"mof.checksum" -join "."),"*" -join ''}
   if(Get-ChildItem $DestinationPath -Exclude $exclusions){
      Get-ChildItem $DestinationPath -Exclude $exclusions | Remove-Item -force
   }
   else {
      Get-ChildItem $DestinationPath | Remove-Item -force
   }
   
   # Get Client Configs except for PullServer
   $configs = $results.rax_dsc_config | Sort -Unique
   # If Client Config Updated, Remove Mof
   foreach( $config in $configs )
   {
      if( !(Test-rsHash $($ConfigPath,$config -join'\') $($ConfigHashPath,$($config,'hash' -join '.') -join'\')) )
      {
         foreach( $server in $($results | ? rax_dsc_config -eq $config) ){
            Remove-rsMof -id $($server.id) -DestinationPath $DestinationPath
         }
         Set-rsHash $($ConfigPath,$config -join'\') $($ConfigHashPath,$($config,'hash' -join '.') -join'\')
      }
   }
   # Create Missing
   foreach( $server in $results ){
      if( !(Test-Path $(($DestinationPath,$($server.id) -join '\'),'mof' -join '.')) -or !(Test-Path $(($DestinationPath,$($server.id) -join '\'),'mof.checksum' -join '.')) )
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
    if(Test-Path $CSVPath){
        $results += Import-Csv -Path $CSVPath | Select name,id,@{Name="rax_dsc_config";Expression=$DedicatedKey}
    }
    else {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1002 -Message "The file path $CSVPath does not exist."
    }
   $results = ($results | ? rax_dsc_config -ne $PullServerConfig)
   
   if($results.id.count -ne (((Get-ChildItem $DestinationPath).count)/2)){
      $testresult = $false
   }
   
   $configs = $results.rax_dsc_config | Sort -Unique
   foreach( $config in $configs )
   {
      if( !(Test-rsHash $($ConfigPath,$config -join'\') $($ConfigHashPath,$($config,'hash' -join '.') -join'\')) )
      {
         $testresult = $false
      }
   }
   foreach( $server in $results ){
      if( !(Test-Path $(($DestinationPath,$($server.id) -join '\'),'mof' -join '.')) -or !(Test-Path $(($DestinationPath,$($server.id) -join '\'),'mof.checksum' -join '.')) )
      {
         $testresult = $false
      }
   }
   return $testresult
}
Export-ModuleMember -Function *-TargetResource
