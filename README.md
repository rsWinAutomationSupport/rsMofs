rsMofs
======

```Posh
rsMofs MyMofs
{
    nodeData = "C:\DevOps\DDI_rsConfigs\nodes.json"
    configPath = "C:\DevOps\DDI_rsConfigs\"
    Ensure = "Present"
}
```
DedicatedKey is the Key Value in the dedicated.csv file that represents the configuration file to use.<br>
CloudKey is the Key Value that is in the metadata on a cloud server that represents the configuration file to use.<br>
PullServerConfig is the configuration name of the Pull Server to exclude from creating mof's.<br>
