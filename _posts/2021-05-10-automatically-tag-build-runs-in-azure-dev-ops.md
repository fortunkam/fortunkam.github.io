---
layout: post
title:  "Automatically tag build runs in Azure DevOps."
date:   2021-05-10 10:00:00 +0100
categories: DevOps Pipelines
author: Matthew Fortunka
---

One little known feature of Azure DevOps Pipelines is the ability to tag a pipeline run.  By default this is a manual process.  
Once the build has completed you select Edit Tags and add the values.

![](/assets/2021-05-10-automatically-tag-build-runs-in-azure-dev-ops/edit_build_tags_1.png "edit tags button")

![](/assets/2021-05-10-automatically-tag-build-runs-in-azure-dev-ops/edit_build_tags_2.png "edit tags entry")

The tags then show up under the title for that run.

![](/assets/2021-05-10-automatically-tag-build-runs-in-azure-dev-ops/edit_build_tags_3.png "edit tags added")

You can add these tags using the REST API.  [This article has a good description of how to get an authentication token for the api](https://tenbulls.co.uk/2020/03/11/querying-azure-devops-rest-api-with-powershell/)

and then add tags to a build run using the following [API call](https://docs.microsoft.com/en-us/rest/api/azure/devops/build/tags/add%20build%20tag?view=azure-devops-rest-6.0).

    PUT https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/tags/{tag}?api-version=6.0
    Authorization: Basic {your base64 encoded PAT}

or alternatively you can add multiples using the [plural version](https://docs.microsoft.com/en-us/rest/api/azure/devops/build/tags/add%20build%20tags?view=azure-devops-rest-6.0)

    POST https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/tags?api-version=6.0
    Authorization: Basic {your base64 encoded PAT}
    Content-Type: application/json

    [ "tag1", "tag2"]


If you want to add tags automatically on every build you need to use the Definition Tag(s) APIs, so [to add a single tag use](https://docs.microsoft.com/en-us/rest/api/azure/devops/build/tags/add%20definition%20tag?view=azure-devops-rest-6.0)...

    PUT https://dev.azure.com/{organization}/{project}/_apis/build/definitions/{DefinitionId}/tags/{tag}?api-version=6.0-preview.2
    Authorization: Basic {your base64 encoded PAT}

[and for multiples](https://docs.microsoft.com/en-us/rest/api/azure/devops/build/tags/add%20definition%20tags?view=azure-devops-rest-6.0)

    POST https://dev.azure.com/{organization}/{project}/_apis/build/definitions/{DefinitionId}/tags?api-version=6.0-preview.2
    Authorization: Basic {your base64 encoded PAT}
    Content-Type: application/json

    [ "tag1", "tag2"]

Unfortunately these definition tags don't seem to be surfaced in the portal anywhere so to retrieve them use [the Get API](https://docs.microsoft.com/en-us/rest/api/azure/devops/build/tags/get%20definition%20tags?view=azure-devops-rest-6.0).

    GET https://dev.azure.com/{organization}/{project}/_apis/build/definitions/{DefinitionId}/tags?api-version=6.0-preview.2
    Authorization: Basic {your base64 encoded PAT}

This will return a JSON list of the tags applied to the Pipeline definition.

    {
        "count": 4,
        "value": [
            "hello",
            "world",
            "test1",
            "test2"
        ]
    }






