rsMofs
======
```Posh
rsMofs My
{
   Name = "CheckMofs"
   DedicatedKey = "rax_dsc_config"
   CSVPath = "C:\DevOps\DDI_rsConfigs\dedicated.csv"
   ConfigPath = "C:\DevOps\DDI_rsConfigs"
   ConfigHashPath = "C:\DevOps"
   DestinationPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration"
   PullServerConfig = "rsPullServer.ps1"
   Ensure = "Present"
}
```
DedicatedKey is the Key Value in the dedicated.csv file that represents the configuration file to use.<br>
PullServerConfig is the configuration name of the Pull Server to exclude from creating mof's.<br>
CSVPath is the Full Path to .csv containing server list.
ConfigPath is the path to the location of .ps1 files
ConfigHashPath is the path to location where checksums of configs will be located
DestinationPath is the location of the .mofs
