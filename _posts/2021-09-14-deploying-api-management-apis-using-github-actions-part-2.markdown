---
layout: post
title: "Deploying API Management APIs using Github Actions - Part 2"
date:   2021-09-16 10:00:00 +0100
categories: 
author: Matthew Fortunka
---

In [Part 1 we talked about the process of taking an API from a yaml file to an ARM template](https://blog.memoryleek.co.uk/2021/09/14/deploying-api-management-apis-using-github-actions.html), in this part we will recreate the process in github actions and give you a pipeline to generate and deploy those templates to Azure.

As before the code for the setup below can all be found at [this repository](https://github.com/fortunkam/apim_api_demo) and makes use of the wonderful [ICanHazDadJoke api](https://icanhazdadjoke.com/api).

Just to recap what we have.
1. A swagger/openAPI definition for our API
2. A config file for the APIM DevOps Resouce Kit Creator tool.
3. Policy files for individual operations and the API overall.

The process is Run the Creator tool to generate the ARM templates, deploy the templates to an Azure APIM Instance and then make sure the APIs are working.  These look like good candidates for phases of our pipeline. 

NOTE: I picked Github Actions to perform the CI/CD part but the same ideas apply to Azure DevOps Pipelines (or indeed any other tool).

## Phase 1: 'Build' the APIs

In this phase we will start with our raw xml and yaml files and convert them to ARM templates using the APIM DevOps Resource Kit creator tool.  The first challenge is getting the tool running on the build agent.  First we need to setup a few things.  This is the scaffold of our Github Actions file.

```
name: 'Deploy API to Azure'

on: 
  push:
    branches:
      - main
jobs:
  build_templates: 
    name: Build ARM templates from yaml
    runs-on: windows-latest
  deploy_templates:
    name: Deploy ARM templates
    needs: build_templates
    runs-on: windows-latest
  verify_api:
    name: Test the APIs
    needs: deploy_templates
    runs-on: ubuntu-latest
```

We want this to run when code is pushed to the main branch only so we are using a push trigger with a branch filter.
Next we want the pipeline to run in three phases, build, deploy and test.  Each phase (or job) will be run on a new agent.  You could do this all in a single job but I prefer to logicially group steps to give better feedback to the observer, the downside to this is you need some extra steps to ensure artifacts flow between jobs.

Lets focus in on the build_templates job and do some setup jobs.

```
build_templates: 
    name: Build ARM templates from yaml
    runs-on: windows-latest
    steps:
        - uses:  actions/checkout@v1
        - name: Setup dotnet '3.1.x'
        uses: actions/setup-dotnet@v1
        with:
            dotnet-version: '3.1.x'
```

Here we get the latest version of our code and make sure that .net 3.1 is installed on the agent.
Now we need to download a version of the APIM Devops Resource Kit, I am choosing to download the latest from the master branch but you could just as easily download a named or tagged version.  I also opted for the zip download rather than adding extra complexity with a git clone (but that would also work just fine), downside is I have to extract the files from the zip.

```
{% raw %}
build_templates: 
    name: Build ARM templates from yaml
    runs-on: windows-latest
    env:
        APIM_RESOURCE_KIT_URI: 'https://github.com/Azure/azure-api-management-devops-resource-kit/archive/refs/heads/master.zip'
        EXTRACTED_PROJECT_PATH: '.\apim_rk\extracted\azure-api-management-devops-resource-kit-master\src\APIM_ARMTemplate\apimtemplate\apimtemplate.csproj'
    steps:
    - uses:  actions/checkout@v1
    - name: Setup dotnet '3.1.x'
        uses: actions/setup-dotnet@v1
        with:
        dotnet-version: '3.1.x'
    - name: Download latest APIM Resource Kit
        shell: pwsh
        run: |
            mkdir apim_rk
            cd apim_rk
            mkdir extracted
            Invoke-WebRequest ${{env.APIM_RESOURCE_KIT_URI}} -outfile .\archive.zip
            Expand-Archive -LiteralPath ".\archive.zip" -DestinationPath ".\extracted" -Force
            cd ..
            mkdir templates
{% endraw %}
```

I am using the powershell core shell here to download the file (Invoke-WebRequest) and unzip it to a new folder I have created.  Lastly I run the extractor tool against my yaml config file, and upload the outputed ARM templates so that the next job can use them.  Here is the complete job.

```
{% raw %}
build_templates: 
    name: Build ARM templates from yaml
    runs-on: windows-latest
    env:
        APIM_RESOURCE_KIT_URI: 'https://github.com/Azure/azure-api-management-devops-resource-kit/archive/refs/heads/master.zip'
        EXTRACTED_PROJECT_PATH: '.\apim_rk\extracted\azure-api-management-devops-resource-kit-master\src\APIM_ARMTemplate\apimtemplate\apimtemplate.csproj'
    steps:
        - uses:  actions/checkout@v1
        - name: Setup dotnet '3.1.x'
        uses: actions/setup-dotnet@v1
        with:
            dotnet-version: '3.1.x'
        - name: Download latest APIM Resource Kit
        shell: pwsh
        run: |
            mkdir apim_rk
            cd apim_rk
            mkdir extracted
            Invoke-WebRequest ${{env.APIM_RESOURCE_KIT_URI}} -outfile .\archive.zip
            Expand-Archive -LiteralPath ".\archive.zip" -DestinationPath ".\extracted" -Force
            cd ..
            mkdir templates
        - name: Generate the ARM templates using the tool
        run: dotnet run create --configFile api.yaml --project ${{env.EXTRACTED_PROJECT_PATH}} -c "Release"
        - name: Upload the built ARM templates
        uses: actions/upload-artifact@main
        with:
            name: armtemplates
            path: templates
{% endraw %}
```

## Phase 2: Deploy the templates to Azure

By the end of phase 1 I have a set of ARM templates stored as build artifacts and waiting to be deployed.  The deploy templates task makes use of the Azure CLI `az deployment group create` and a few GitHub secrets.

```
{% raw %}
  deploy_templates:
    name: Deploy ARM templates
    needs: build_templates
    runs-on: windows-latest
    steps:
      - uses: actions/download-artifact@main
        name: Download Templates
        with: 
          name: armtemplates
          path: templates
      - name: "Login via Azure CLI"
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }} 
      - name: Deploy the Backends
        run: az deployment group create -g ${{ secrets.AZURE_RESOURCE_GROUP }} --template-file ".\templates\mfapim-backends.template.json" --parameters ApimServiceName=${{ secrets.AZURE_APIM_NAME }}
      - name: Deploy the API
        run: az deployment group create -g ${{ secrets.AZURE_RESOURCE_GROUP }} --template-file ".\templates\ICanHazDadJoke.api.template.json" --parameters ApimServiceName=${{ secrets.AZURE_APIM_NAME }}
      - name: Azure logout
        run: az logout
{% endraw %}
```
Firstly we need to download the artifacts from the previous step, this is a seperate job remember so we need to assume this is different agent running the code.

Most of the secrets used here are pretty self explanatory.
`AZURE_RESOURCE_GROUP` is the resource group containing our APIM.
`AZURE_APIM_NAME` is the APIM
`AZURE_CREDENTIALS` however is a little more complex and relies on you creating a service principal in your Azure AD.  This is the 'user' that has permissions to deploy to your Azure Subscription.  A good explanation on how to set it up can be found in the [Azure CLI Github Action doc here](https://github.com/marketplace/actions/azure-cli-action#configure-azure-credentials-as-github-secret).
Lastly we log out our Azure credentials when we are done.

## Phase 3: Test the API

To finish we want to double check our APIs are callable so a couple of curl commands will do here.
As part of the API definition I have added a link to the standard unlimited APIM Product. Meaning we can use the Product Key to call the API (this is stored in a Secret).

```
{% raw %}
  verify_api:
    name: Test the APIs
    needs: deploy_templates
    runs-on: ubuntu-latest
    steps:
      - name: Call Single API
        run: |
          curl --request GET --url ${{ secrets.AZURE_APIM_BASE_URL }} --header 'ocp-apim-subscription-key: ${{ secrets.AZURE_APIM_SUBSCRIPTION_KEY }}'
      - name: Call Search API
        run: |
          curl --request POST --url "${{ secrets.AZURE_APIM_BASE_URL }}/search" --header 'content-type: application/json' --header 'ocp-apim-subscription-key: ${{ secrets.AZURE_APIM_SUBSCRIPTION_KEY }}' --data '{"term" : "cat","page" : 1,"limit" : 5}'
{% endraw %}
```

The end result is a very satisfying 3 step pipeline.

![](/assets/2021-09-14-deploying-api-management-apis-using-github-actions-part-2/action_complete.png "Github action deploying API to APIM")

you even get to see the dad jokes appear in the actions logs!

![](/assets/2021-09-14-deploying-api-management-apis-using-github-actions-part-2/dad_joke.png "Dad Joke in Github Actions Log")