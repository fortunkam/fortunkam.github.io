---
layout: post
title: "Using ARM Deployment scripts to setup databases"
date:   2022-09-01 10:00:00 +0100
categories: 
author: Matthew Fortunka
---

[Deployment scripts](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep) are a great addition to ARM/Bicep that let you execute custom code as part of a deployment.  The scripts run as an Azure Container Instance and, if successful, are cleaned up once complete. 

As part of the setup for my last blog post ([importing SOAP UIs to API Management using Terraform]({% post_url 2022-08-24-importing-soap-apis-to-api-management-using-terraform %})) I wanted to provision some resources for an API.  The API would be a simple .net framework WCF service (SOAP/WSDL would be generated for me) hosted in Azure App Service that would talk to an Azure SQL Database, supporting both parts would be Application Insights.  App Service has [deployment center](https://docs.microsoft.com/en-us/azure/app-service/deploy-continuous-deployment?tabs=github) for pushing the application code automatically but that still leaves the problem of setting up the database.  (Worth noting I got so consumed by the database problem, I completely forgot about the Deployment Center piece for App Service, one for future me to deal with!)

With Database setup you have a couple of options..
* Have the application set-up the database.  This is what CRMs like EntityFramework try to do ([EF migrations](https://docs.microsoft.com/en-us/ef/core/managing-schemas/migrations/?tabs=dotnet-core-cli) are very cool and worth spending time looking into).  The downside here is the application is now split purpose when it comes to permissions.  It needs elevated permissions to configure the database but should only have minimal permissions when running.
* Have a multi-stage deployment script (e.g. Deploy resources, configure DB, deploy app)
* Deploy the DB schema as part of the Infrastructure deploy.

All are valid, as an academic exercise my goal for the project was "could I do everything from the `az deployment` command?"

All the bicep that follows can be found in my [github repository here](https://github.com/fortunkam/wcf_database_appinsights/tree/main/env).

The following resources will be deployed
* Azure SQL Server (S0)
* Azure SQL Database
* Azure App Service Plan (S1)
* Azure Web Application
* Log Analytics Workspace
* Application Insights

I also deploy a SQL firewall rule for my local machine so that I can diagnose any issues.

The project itself contains a couple of powershell scripts and a SQL file (which defines the tables, procs and data to be deployed).

The deployment script resource comes in 2 flavours, AZ CLI and AzurePowershell.  I chose to use Powershell for this example, mostly for the support of `Invoke-SqlCmd`.

Here is the starting point for a deployment script in Bicep...

```
resource createDatabaseTable 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${prefix}-create-db-table'
  location: resourceGroupLocation
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '6.4'
    scriptContent: loadTextContent('./deploy_database.ps1')
    arguments: '-dbName \'${sqldatabase.name}\' -serverName \'${sqlserver.name}\' -sqlUser \'${sqlUser}\' -sqlPassword \'${sqlPassword}\' -resourceGroupName \'${resourceGroup().name}\' -scriptUri \'${scriptUri}\''
    timeout: 'PT1H'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}
```

I define a script called deploy_database.ps1 in my project and load that into the bicep definition using `loadTextContent`.

The script takes a set of parameters that must be passed in using the **arguments** property.   This lets me map bicep variables into powershell.  Here is the equivalent script definition..

```

param([string] $dbName, 
    [string] $serverName, 
    [string] $sqlUser, 
    [string] $sqlPassword,
    [string] $resourceGroupName,
    [string] $scriptUri)

Install-Module -Name SqlServer -Force -Confirm:$false -AllowClobber -Scope CurrentUser
Write-Output "Imported module"

$fullSqlServerFQDN = "$serverName.database.windows.net"

$sqlQuery = (Invoke-WebRequest -Uri $scriptUri -Method 'GET').Content

$sqlParams = @{
    'Database'       = $dbName
    'ServerInstance' = $fullSqlServerFQDN
    'Username'       = $sqlUser
    'Password'       = $sqlPassword
    'Query'          = $sqlQuery
}
Invoke-Sqlcmd @sqlParams
```

The script tries to esnure the required module is installed before running the sql command.  The SQL Command text is downloaded from the publicly available repo.  If you are not happy having the SQL exposed publicly you could also upload the file to a blob storage account and expose via a SAS token.

What you will find if you try to run this is it will fail!  The container instance the code runs in, needs to be allowed through the Azure Firewall. So we amend our script to read the outbound IP currently in use and add it to the Firewall.

```
param([string] $dbName, 
    [string] $serverName, 
    [string] $sqlUser, 
    [string] $sqlPassword,
    [string] $resourceGroupName,
    [string] $scriptUri)

Install-Module -Name SqlServer -Force -Confirm:$false -AllowClobber -Scope CurrentUser
Write-Output "Imported module"
Get-Module SqlServer -ListAvailable | Write-Output
$publicIp = (Invoke-WebRequest http://myexternalip.com/raw).Content -replace "`n"
Write-Output $publicIp

Remove-AzSqlServerFirewallRule -FirewallRuleName create-table-deployment-script -ServerName $serverName -ResourceGroupName $resourceGroupName -Force

Start-Sleep -Seconds 10

New-AzSqlServerFirewallRule -ServerName $serverName -FirewallRuleName create-table-deployment-script -StartIpAddress $publicIp -EndIpAddress $publicIp -ResourceGroupName $resourceGroupName

Start-Sleep -Seconds 120

$sqlQuery = (Invoke-WebRequest -Uri $scriptUri -Method 'GET').Content

Write-Output $sqlQuery

$fullSqlServerFQDN = "$serverName.database.windows.net"

$sqlParams = @{
    'Database'       = $dbName
    'ServerInstance' = $fullSqlServerFQDN
    'Username'       = $sqlUser
    'Password'       = $sqlPassword
    'Query'          = $sqlQuery
}
Invoke-Sqlcmd @sqlParams
```

Note: I added some sleeps to the script because it can take a few seconds for the firewall rules to take effect, 2 minutes is probably overkill and need to optimise this.

We are nearly there but right now this will also fail because the AzSQLServerFirewallRule command is not authorised to talk to the SQL Server, there is no identity associated with the deployment script, back to Bicep to add those resources.

```
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${prefix}-script-identity'
  location: resourceGroupLocation  
}

resource scriptIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${prefix}-script-identity', contributorRoleDefinitionId, resourceGroup().id)
  properties: {
    roleDefinitionId: contributorRoleDefinitionResourceId
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource createDatabaseTable 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${prefix}-create-db-table'
  location: resourceGroupLocation
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  dependsOn: [scriptIdentityRoleAssignment]
  properties: {
    azPowerShellVersion: '6.4'
    scriptContent: loadTextContent('./deploy_database.ps1')
    arguments: '-dbName \'${sqldatabase.name}\' -serverName \'${sqlserver.name}\' -sqlUser \'${sqlUser}\' -sqlPassword \'${sqlPassword}\' -resourceGroupName \'${resourceGroup().name}\' -scriptUri \'${scriptUri}\''
    timeout: 'PT1H'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}
```

Here I create a new User Assigned Managed Identity and assign it the Contributor role on the resource group.  Then the identity is associated with the deployment script and everything works.  I have a configured database ready to accept requests from my app.

But wait, there is a problem.  The SQL Server also needs firewall rules for the App Service (so that the app can talk to the DB).  Bicep has a bit of problem here because the Outbound IP addresses used are only allocated after deploy (and can't be referenced from another bicep resource), so enter deployment scripts again to query the list of IP addresses and add the entries to the firewall.

```
resource createWebFirewallRules 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${prefix}-create-web-firewall-rules'
  location: resourceGroupLocation
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '6.4'
    scriptContent: loadTextContent('./add_webapp_outboundip_to_sql.ps1')
    arguments: '-sqlServerName \'${sqlServerName}\' -webAppName \'${webApplication.name}\' -resourceGroupName \'${resourceGroup().name}\''
    timeout: 'PT1H'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}
```

and the equivalent powershell script

```
param ([string] $sqlServerName, 
    [string] $webAppName, 
    [string] $resourceGroupName)

    $existingRules = Get-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName | where FirewallRuleName -Match '^wcf-app-sql-web-.*'

    $existingRules | ForEach-Object {
        Remove-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName $_.FirewallRuleName
    }

    Start-Sleep -Seconds 5

    $outboundAddressesString = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $webAppName | Select-Object OutboundIpAddresses

    $outboundAddressesString.OutboundIpAddresses.Split(",") | ForEach-Object {
        New-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName "wcf-app-sql-web-$($_.Trim())" -StartIpAddress $_.Trim() -EndIpAddress $_.Trim()
    }
```

