---
layout: post
title: "Adding Diagnostic Settings to API Management (and other resources) using ARM templates"
date:   2021-08-18 10:00:00 +0100
categories: APIM Azure ARM
author: Matthew Fortunka
---

This one is a bit of a gotcha around building an API Management (APIM) resource using ARM templates and concerns the diagnostic settings, shown below....


![](/assets/2021-08-18-adding-diagnostic-settings-to-api-management-using-arm-templates/diagnostic_settings_portal.png "API Management diagnostic settings in the Azure Portal")

If you extract the Template (`Export Template` option) from the Azure portal you will notice that these settings are not included.  The reason is that these are actually resources of the Azure Monitor implementation not the APIM.

For more details, take a look at the [Azure Monitor documentation here](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/resource-manager-diagnostic-settings).

Here is a sample ARM resource template that adds all the available logger types (Event Hub, Storage and Log Analytics)

    {
        "type": "Microsoft.ApiManagement/service/providers/diagnosticSettings",
        "apiVersion": "2017-05-01-preview",
        "name": "[concat(parameters('apimName'),'/microsoft.insights/', parameters('diagnosticSettingName'))]",
        "dependsOn": [],
        "properties": {
            "workspaceId": "[parameters('diagnosticWorkspaceId')]",
            "storageAccountId": "[parameters('storageAccountId')]",
            "eventHubAuthorizationRuleId": "[parameters('eventHubAuthorizationRuleId')]",
            "eventHubName": "[parameters('eventHubName')]",
            "metrics": [
                {
                    "category": "AllMetrics",
                    "enabled": true,
                    "retentionPolicy": {
                        "enabled": false,
                        "days": 0
                    }
                }
            ],
            "logs": [
                {
                    "category": "GatewayLogs",
                    "categoryGroup": null,
                    "enabled": true,
                    "retentionPolicy": {
                        "enabled": false,
                        "days": 0
                    }
                },
                {
                    "category": "WebSocketConnectionLogs",
                    "categoryGroup": null,
                    "enabled": false,
                    "retentionPolicy": {
                        "enabled": false,
                        "days": 0
                    }
                }
            ]
        }
    }

A few bits to call out...

The resource type is `"Microsoft.ApiManagement/service/providers/diagnosticSettings"` this denotes a sub resource provider used associated with API Management.
The resource name is then `"[concat(parameters('apimName'),'/microsoft.insights/', parameters('diagnosticSettingName'))]"`, joining together the specific api instance and the name of the new diagnostic setting.

