---
layout: post
title:  "Promoting Maven Packages to Release Views using the Azure DevOps Artifacts REST API."
date:   2020-05-27 11:19:38 +0100
categories: Maven DevOps Pipelines Artifacts
excerpt: Azure DevOps artifacts has the ability to promote Packages between different states, this is useful if you want to test different versions of a package with limited audiences (who accept the risk).
author: Matthew Fortunka
---
WARNING: I can’t find any reference to this API in any of the official documentation, it is consumed by the azure devops site so should be fairly stable but could be changed without warning.   Use at your own risk!

ADDITIONAL WARNING: I am not a Java/Maven developer, I am happy to take recommendations for how to improve this process.

PROBLEM: How do I promote my Maven Package to a PreRelease/Release view in Azure DevOps Artifacts with a script?

Azure DevOps artifacts has the ability to promote Packages between different states, this is useful if you want to test different versions of a package with limited audiences (who accept the risk).

![](/assets/2020-05-28-maven-artifacts-devops/Portal%20Promote%20Option.png "Promote")

If you want make this part of your CI/CD pipeline you run into challenges, a marketplace extension exists (link)but this is only supported for NPM/Nuget packages  (and not Maven).

Digging into the [repo associated with the extension](https://github.com/renevanosnabrugge/vsts-promotepackage-task) and this [excellent blog post](https://roadtoalm.com/2017/01/16/programmatically-promote-your-package-quality-with-release-views-in-vsts/) I found that it is using the DevOps REST API under the hood. However the reason it only supports NPM and Nuget is that there is no PATCH REST API for maven Sad smile

So how is the Portal doing it? Lets inspect the traffic (F12 Network tab in a Chromium browser).

![](/assets/2020-05-28-maven-artifacts-devops/Portal%20Network%20trace.png "Network Trace")

It looks like there is an API called packagesBatch that does the update. So lets try to call it with a PAT token ([instructions here](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page)).

    {% raw %}
    POST https://pkgs.dev.azure.com/{{DEVOPS_ORG}}/{{DEVOPS_PROJECT_GUID}}/_apis/packaging/feeds/{{DEVOPS_FEED_GUID}}/maven/packagesBatch
    Content-Type: application/json
    accept: application/json;api-version=5.0-preview.1;excludeUrls=true;enumsAsNumbers=true;msDateFormat=true;noArrayWrap=true
    Authorization: Basic :{{DEVOPS_PAT_TOKEN}}

    {
        "data":
        {
            "viewId":"{{DEVOPS_FEED_VIEW_RELEASE_GUID}}"
        },
        "operation":0,
        "packages":[
            {
                "group":"{{ARTIFACT_GROUP_NAME}}",
                "artifact":"{{ARTIFACT_NAME}}",
                "version":"{{ARTIFACT_VERSION}}"
            }
        ]
    }
    {% endraw %}

That seems to work! Now by changing the viewId to the release GUID we can promote to that view too.

Here is the sample payload for my request..

    {% raw %}
    {
        "data":
        {
            "viewId":"0b1177ed-e3b3-46c5-a42c-7a3420ae109c"
        },
        "operation":0,
        "packages":[
            {
                "group":"com.memoryleek.javaexperiments","artifact":"maven-test",
                "version":"1.2.168"
            }
        ]
    }
    {% endraw %}

You can use the standard REST API to get the Project GUID, the Feed GUID and the Feed View GUIDs. (requests shown below).  The DEVOPS org can be seen when you sign into the portal.

    {% raw %}
    #Get the Project GUID
    GET https://dev.azure.com/{{DEVOPS_ORG}}/_apis/projects?api-version=6.0-preview.4
    Authorization: Basic :{{DEVOPS_PAT_TOKEN}}

    ###

    #Get the Feed GUID
    GET https://feeds.dev.azure.com/{{DEVOPS_ORG}}/{{DEVOPS_PROJECT_GUID}}/_apis/packaging/feeds?api-version=6.0-preview.1
    Authorization: Basic :{{DEVOPS_PAT_TOKEN}}

    ###

    #Get the Feed View GUIDs
    GET https://feeds.dev.azure.com/{{DEVOPS_ORG}}/{{DEVOPS_PROJECT_GUID}}/_apis/packaging/Feeds/{{DEVOPS_FEED_GUID}}/views?api-version=6.0-preview.1
    Authorization: Basic :{{DEVOPS_PAT_TOKEN}}
    {% endraw %}