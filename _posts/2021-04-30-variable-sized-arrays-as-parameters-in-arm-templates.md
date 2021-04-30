---
layout: post
title:  "Variable sized arrays as parameters in ARM templates."
date:   2021-04-30 10:00:00 +0100
categories: ARM
author: Matthew Fortunka
---

Consider the scenario, you are deploying an ARM template for an Azure storage account.  You want to reuse the same template in multiple environments.  The storage account is using the local firewall to restict access.  Each environment has a different set of ip rules that need to be applied (both in number and values).  How do you ensure that the ipRules can be passed as an array and applied correctly?  (Note: I am using a storage account and ipRules as an example here, the same should apply to any array property on an ARM template)

This is a typical ARM template for a storage account

    {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "resources": [
            {
                "name": "mfdevstorage1",
                "type": "Microsoft.Storage/storageAccounts",
                "apiVersion": "2019-06-01",
                "location": "[resourceGroup().location]",
                "kind": "StorageV2",
                "sku": {
                    "name": "Premium_LRS",
                    "tier": "Premium"
                },
                "properties" :{
                    "networkAcls" : {
                        "defaultAction" : "Deny",
                        "ipRules" : [
                            {
                                "value": "215.6.5.23",
                                "action": "Allow"
                            },
                            {
                                "value": "215.6.5.24",
                                "action": "Allow"
                            }
                        ]
                    }
                }
            }
        ]
    }

We want to be able to pass that "ipRules" section in as a parameter. Something like this...

    "parameters": {
        "ipRuleArray": {
            "type": "array"
        }
    },

There are 2 ways this can work, if my parameter value matches the objects expected in the arm template I can just use the parameter directly.  So if I pass in this...

    {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "ipRuleArray": {
                "value" :  [
                    {
                        "value" : "212.56.109.20",
                        "action" : "Allow"
                    },
                    {
                        "value" : "212.56.109.21",
                        "action" : "Allow"
                    }
                ]
            }
        }
    }

My ipRules becomes this...

    "networkAcls" : {
        "defaultAction" : "Deny",
        "ipRules" : "[parameters('ipRuleArray')]"
    }

However if I only want to pass in the ip address like this...

    {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "ipRuleArray": {
                "value" :  [
                    "212.56.109.20",
                    "212.56.109.21"
                ]
            }
        }
    }

I can make use of the `copy` property to generate the required objects, like so..

    "networkAcls" : {
        "defaultAction" : "Deny",
        "copy": [
            {
                "name" : "ipRules",
                "count" : "[length(parameters('ipRuleArray'))]",
                "input" : {
                    "value" : "[parameters('ipRuleArray')[copyIndex('ipRules')]]",
                    "action": "Allow"
                }

            }
        ]
    }

Now when I call the template for each environment, only the parameters need to change.





