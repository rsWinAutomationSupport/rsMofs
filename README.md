## rsMofs

DSC Module for automatically generating mof file and related checksums based on input data within a json formatted document and regenerate those mof files based on the state of other environment variables that are used within Rackspace Automation platform.

### Parameters

- *nodeData* - json file, which contains managed node data
- *configPath* - location of DSC configuration scripts used for mof creation
- *configHashPath* - (optional) location of configuration file checksum files, used to detect updates to configuration files. Default value is as defined for *configPath* parameter
- *mofDestPath* - (optional) location of where all mof and their checksum files need to be saved. Default value is `"C:\Program Files\WindowsPowerShell\DscService\Configuration"`
- *pullConfig* - (optional) name of DSC configuration file for PULL server itself, if it is present in *nodeData*. Used as a filter in order to skip mof file generation for pull server. Default value is `rsPullServer.ps1`. 

### Example 

```Posh
rsMofs MyMofs
{
    nodeData = "C:\DevOps\DDI_rsConfigs\nodes.json"
    configPath = "C:\DevOps\DDI_rsConfigs\"
    Ensure = "Present"
}
```

