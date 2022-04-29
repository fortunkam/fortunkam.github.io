---
layout: post
title: "Mounting an Azure Storage File Share to an Azure Web App"
date:   2022-04-29 10:00:00 +0100
categories: 
author: Matthew Fortunka
---

This week Microsoft announced the arrival of the preview of [Mounting Azure Storage as a local share in App Service](https://docs.microsoft.com/en-us/azure/app-service/configure-connect-to-azure-storage?tabs=portal&pivots=code-windows)

I was curious as to how this works in practice so spun up a [simple sample app](https://github.com/fortunkam/AppService-StorageMount) to test it.

The project consists of a [bicep file](https://github.com/fortunkam/AppService-StorageMount/blob/main/env/deploy.bicep) to deploy the required resources (basically an app service plan, web app and a storage account).  This can be deployed using `az deployment group create --template-file ./deploy.bicep -g RESOURCEGROUPNAME`

The magic of the bicep file is web app deploy....

```
resource webApplication 'Microsoft.Web/sites@2021-03-01' = {
  name: '${prefix}api'
  location: location
  properties: {
    serverFarmId: serverFarm.id
    siteConfig: {
      appSettings: [
        {
          name: 'MountPath'
          value: '../../..${mountPath}'
        }
      ]
      azureStorageAccounts: {
        blobmount : {
          type: 'AzureFiles'
          accountName: storageAccount.name
          shareName: fileshare.name
          mountPath: mountPath
          accessKey: storageAccount.listKeys().keys[0].value
        }
      }
    }
    
  }
  kind: 'app'
}
```

Lets focus on the new azureStorageAccounts section..

```
azureStorageAccounts: {
    blobmount : {
        type: 'AzureFiles'
        accountName: storageAccount.name
        shareName: fileshare.name
        mountPath: mountPath
        accessKey: storageAccount.listKeys().keys[0].value
    }
}
```

I define a name for the resource (blobmount) and specify the details of the storage account (would be nice to be able to do this with a managed identity but access keys are the way to go for now).
I also provide the path that the share will be available on,  in my case '/mounts/appservice' (all the filepaths need to start with '/mounts/')

When the mount is created, it appears at that path at the root folder (i.e. c: drive on windows) so the path the app will use will be  '../../../mounts/appservice', because the code for my dotnet app will run from the 'c:\home\site\wwwroot'.   You can see both of these paths by viewing the debug console in Kudu (Advanced Tools on the app service)

![](/assets/2022-04-29-mounting-file-share-to-app-service/wwwroot.png "Kudu showing c:\home\site\wwwroot")

![](/assets/2022-04-29-mounting-file-share-to-app-service/appservice.png "Kudu showing c:\mounts\appservice")

Now we deploy the app to the app service.  This is a simple dotnet Minimal API with a single POST operation that writes the body to a json file.  The File Path is loaded from configuration so that I can provide a different value when testing locally.

```
app.MapPost("/savefile",([FromBody]object content, [FromServices]IConfiguration configuration) => {
    var path = configuration.GetValue<string>("MountPath");
    var fileName = DateTime.Now.ToString("yyyyMMddHHmmss") + ".json";
    var filePath = $"{path}/{fileName}";

    File.WriteAllText(filePath, content.ToString());
    return $"File Written to {filePath}";

});
```

You can see the files being written to the file share using Azure Storage Explorer

![](/assets/2022-04-29-mounting-file-share-to-app-service/storageexplorer.png "Kudu showing c:\mounts\appservice")

