rsMofs
======
```Posh
rsMofs My
{
    Name = "MyMofs"
    DedicatedKey = "rax_dsc_config"
    CloudKey = "rax_dsc_config"
    PullServerConfig = "rsPullServer.ps1"
    Ensure = "Present"
}
```
DedicatedKey is the Key Value in the dedicated.csv file that represents the configuration file to use.<br>
CloudKey is the Key Value that is in the metadata on a cloud server that represents the configuration file to use.<br>
PullServerConfig is the configuration name of the Pull Server to exclude from creating mof's.<br>
