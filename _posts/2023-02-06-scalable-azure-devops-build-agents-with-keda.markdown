---
layout: post
title: "Scalable Azure DevOps Build Agents with KEDA"
date:   2023-02-06 10:00:00 +0100
categories: DevOps KEDA
author: Matthew Fortunka
---

The compute behind Azure DevOps pipelines comes in the form of build agents.  By default pipelines will run on a Microsoft Hosted agent (typically an Azure Virtual Machine running in the same geography as your [Azure DevOps Organisation](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops&tabs=yaml#networking)).  The problems with Hosted agents come when you need more control over the machines that run them, broadly these issues fall into the following categories..

* Agents need access to private resources (e.g. endpoints on a network)
* Agents have specific hardware requirements (e.g. GPU)
* Agents have specific software requirements (e.g. per-seat licences)

To solve these requirements you can provision your own agents, these can be physical machines, cloud based virtual machines or, most recently, containers.  Once provisioned the agent is associated with an agent pool and will periodically check the queue for new work. Full details on provisioning all types of "Self-host" agents can be found [here](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops). 

The most recent addition is the ability to run agents as [container images](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops).  It is possible to run agents on something like Azure Container Instances but the real power comes from using an Orchestrator like Kubernetes.  A typical build agent needs to meet the following criteria

1. A new "clean" agent per job/request.  You don't want side-effects leaking to subsequent jobs.
2. Agents start up fast.  The fast agents can be provisioned the fewer items in the queue.
3. The number of agents scales according to the number of messages in the queue.  

Points 1 and 2 are where Kubernetes shines, additional pods or jobs can be added in seconds. The scaling requirement (Point 3) is slightly more challenging however.  Kubernetes has the [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale) will vary the number of pods in a replicaset based on resource metrics (like cpu or memory) but can't easily be connected to external event sources (like our Azure DevOps pending jobs Queue) without tinkering at the API level.

Enter **[Kubernetes Event-driven Autoscaling (KEDA)](https://keda.sh/)**, and more specifically, the [KEDA scaler for Azure Pipelines](https://keda.sh/docs/2.9/scalers/azure-pipelines/).  The KEDA scaler acts on a new Kubernetes resource called a ScaledObject (for pods) or a ScaledJob (for jobs), we provide the agent pool id, some credentials and it figures out how many pods/jobs are needed.

*QUICK NOTE: For the rest of the description I will be using ScaledJobs, rather than ScaledObjects.  I ran into some side-effects with ScaledObjects where pods weren't cleaned up correctly in Azure DevOps that needs further investigation.*

A really good article on [scaling Azure DevOps agents with KEDA can be found on the official KEDA blog](https://keda.sh/blog/2021-05-27-azure-pipelines-scaler/).  In it they detail one of the challenges around working with ScaledJobs specifically around the need for a [placeholder agent](https://keda.sh/blog/2021-05-27-azure-pipelines-scaler/#placeholder-agent).  To summarize, Azure DevOps won't queue new jobs if there are no agents listed (which there won't be if you are scaling on demand).  The workaround is to have a placeholder agent present in the pool but Disabled!  This means our agent deployment needs to have both a ScaledJob definition (for the actual agents) and a deployment containing a single pod (our placeholder). We handle disabling this agent in our deployment script using the Azure DevOps REST APIs.

Our Helm chart will deploy the following resources.

![Helm Chart resources](/assets/2023-02-03/helm_chart.drawio.png)

|Resource Name|Description|
|---|---|
|Namespace|Each named instance of the helm chart will be contained within its own namespace|
|Deployment (Placeholder)|This deploys a single pod using the build agent container image|
|ScaledJob (Agents)|This is the KEDA magic!  This definition points at the Azure DevOps Agent Pool and will provision new Kubernetes jobs for each waiting run|
|Secret (Dockerconfig)|Contains the authentication details for the Azure Container Registry so that the chart can pull the correct images|
|Secret (Azure DevOps)|Contains the credentials used by KEDA to monitor the pending pipeline runs, this is mounted into the Pod/Jobs as an environment variable|  



So how does this work in practice...

## Step 1: Deploy the infrastructure

Well first we are going to need a kubernetes cluster.  I have provided some [bicep files](https://github.com/fortunkam/keda-azdo-build-agent/tree/main/infrastructure/core) to deploy the cluster to your subscription (and also a [github actions pipeline](https://github.com/fortunkam/keda-azdo-build-agent/blob/main/.github/workflows/deploy_infrastructure.yaml) that shows the steps)

In the example below I am using github actions environment variables to provide the following details

|Name|Description|
|---|---|
|`{%raw%}${{vars.LOCATION}}{%endraw%}`| The Azure region to deploy your resources too (I used uksouth)|
|`{%raw%}${{vars.RESOURCE_PREFIX}}{%endraw%}`|A prefix added to all resources|



```
# Make sure you have the KedaPreview feature registered
az feature register --name AKS-KedaPreview --namespace Microsoft.ContainerService
az provider register -n Microsoft.ContainerService

# Deploy the bicep file
az deployment sub create -f "./main.bicep" --location "{%raw%}${{vars.LOCATION}}{%endraw%}" -p resourcePrefix="{%raw%}${{vars.RESOURCE_PREFIX}}{%endraw%}"
```

Once deployed you will have a resource group, an Azure Container Registry and an Azure Kubernetes service.

*QUICK NOTE: This should be all you need to do, the bicep file contains a flag to enable KEDA on the cluster, however at the time of writing this wasn't working so it needs to be installed manually*

To [Install KEDA](https://keda.sh/docs/2.9/deploy/#helm), run the following (you will need the Azure CLI, Helm and Kubectl installed).
```
# Connect to the AKS cluster from the CLI
az aks get-credentials --name "{%raw%}${{ vars.RESOURCE_PREFIX }}{%endraw%}-aks" --resource-group "{%raw%}${{ vars.RESOURCE_PREFIX }}{%endraw%}-rg"

#Install KEDA
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --namespace keda
```

## Step 2: Build and Push the Agent Image

The [Image for the build agent](https://github.com/fortunkam/keda-azdo-build-agent/tree/main/src/azdo_build_agent) is based on the example given in the [Microsoft Learn article](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops).  We want a fresh agent for each request so we are using the `--once` flag described [here](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops#start-the-image).

Once again a [Github action has been provided to describe the build and upload to the Container Registry](https://github.com/fortunkam/keda-azdo-build-agent/blob/main/.github/workflows/agent_image.yaml). 
The action uses the `az acr build` command to do the heavy lifting. The image is tagged with latest and the Run id.

```
acrName="{%raw%}${{vars.RESOURCE_PREFIX}}{%endraw%}acr"
az acr build -r $acrName -t "azdo-build-agent:latest" -t "azdo-build-agent:{%raw%}${{ github.run_id }}{%endraw%}" "./src/azdo_build_agent"
```

## Step 3: Build and Push the Helm Chart

The build agent resources are deployed using a [helm chart](https://github.com/fortunkam/keda-azdo-build-agent/tree/main/helm/scaled-azdo-build-agent),  I have a [separate action to build, version and publish the helm chart](https://github.com/fortunkam/keda-azdo-build-agent/blob/main/.github/workflows/agent_helm.yaml) to the Azure Container Registry (ACR can act as an OCI repository). 
The action ensures that helm is installed before doing a `helm package` and `helm push`

```
# Package the chart
helm package "./helm/scaled-azdo-build-agent" --app-version "{%raw%}${{env.HELM_APP_VERSION}}{%endraw%}" --version "{%raw%}${{env.HELM_CHART_VERSION}}{%endraw%}"

# Log into the registry
accessToken=$(az acr login --name "{%raw%}${{env.ACRNAME}}{%endraw%}" --expose-token --query accessToken -o tsv)
echo $accessToken | helm registry login --username "00000000-0000-0000-0000-000000000000" --password-stdin "{%raw%}${{env.ACRNAME}}{%endraw%}.azurecr.io"

# Push the versioned chart
helm push "{%raw%}${{env.HELM_CHART_NAME}}{%endraw%}-{%raw%}${{env.HELM_CHART_VERSION}}{%endraw%}.tgz" "oci://{%raw%}${{env.ACRNAME}}{%endraw%}.azurecr.io"
```

## Step 4: Deploy to the cluster.

[In the final pipeline](https://github.com/fortunkam/keda-azdo-build-agent/blob/main/.github/workflows/deploy_agents.yaml) we do a `helm upgrade` to grab the versioned chart from the repository and push it to the cluster.  The following parameters must be provided when running the steps (in my case I use a combination of environment variables, environment secrets and local variables)

|Name|Description|
|---|---|
|`{%raw%}${{env.AKS_NAME}}{%endraw%}`|The AKS cluster name (e.g. $RESOURCE_PREFIX + **-aks**)|
|`{%raw%}${{env.RESOURCE_GROUP}}{%endraw%}`|The resource group name (e.g. $RESOURCE_PREFIX + **-rg**)|
|`{%raw%}${{env.ACR_NAME}}{%endraw%}`|The Azure Container Registry name (e.g. $RESOURCE_PREFIX+ **acr**)|
|`{%raw%}${{env.HELM_RELEASE_NAME}}{%endraw%}`|The name given to this specific deployment of agents (can have multiple on a cluster|
|`{%raw%}${{env.HELM_CHART_NAME}}{%endraw%}`|The name of the helm chart (typically **scaled-azdo-build-agent**)|
|`{%raw%}${{vars.DOCKER_IMAGE_TAG}}{%endraw%}`|The version of the agent image to deploy (typically **latest**)|
|`{%raw%}${{secrets.AZDO_URL}}{%endraw%}`|The url of your Azure DevOps Organisation (e.g. https://dev.azure.com/myorg)|
|`{%raw%}${{secrets.AZDO_PAT}}{%endraw%}`|A Personal Access Token from Azure DevOps with Permissions to Manage Agent Pools|
|`{%raw%}${{vars.AZDO_AGENT_POOL}}{%endraw%}`|The name of the agent pool to add the agents to|

```
# Log into the AKS cluster
az aks get-credentials --name "{%raw%}${{env.AKS_NAME}}{%endraw%}" --resource-group "{%raw%}${{env.RESOURCE_GROUP}}{%endraw%}"

# Get the ACR credential so that helm can grab the container image from the repository
acrCred=$(az acr credential show -n "{%raw%}${{env.ACR_NAME}}{%endraw%}" --query passwords[0].value -o tsv)

# Log into the ACR Reqistry to retrieve the helm chart
accessToken=$(az acr login --name "{%raw%}${{env.ACR_NAME}}{%endraw%}" --expose-token --query accessToken -o tsv)
echo $accessToken | helm registry login --username "00000000-0000-0000-0000-000000000000" --password-stdin "{%raw%}${{env.ACR_NAME}}{%endraw%}.azurecr.io"

# Apply the Helm chart with some parameters.

helm upgrade {%raw%}${{env.HELM_RELEASE_NAME}}{%endraw%} \
    "oci://{%raw%}${{env.ACR_NAME}}{%endraw%}.azurecr.io/{%raw%}${{env.HELM_CHART_NAME}}{%endraw%}" \
    --version "{%raw%}${{vars.HELM_CHART_VERSION}}{%endraw%}" \
    --install \
    --wait \
    --set image.repository="{%raw%}${{env.ACR_NAME}}{%endraw%}.azurecr.io/azdo-build-agent" \
    --set image.tag="{%raw%}${{vars.DOCKER_IMAGE_TAG}}{%endraw%}" \
    --set azdo.url="{%raw%}${{secrets.AZDO_URL}}{%endraw%}" \
    --set azdo.agentManagementToken="{%raw%}${{secrets.AZDO_PAT}}{%endraw%}" \
    --set azdo.pool.name="{%raw%}${{vars.AZDO_AGENT_POOL}}{%endraw%}" \
    --set imageCredentials.registry="{%raw%}${{env.ACR_NAME}}{%endraw%}.azurecr.io" \
    --set imageCredentials.username="{%raw%}${{env.ACR_NAME}}{%endraw%}" \
    --set imageCredentials.password="$acrCred"
```

Lastly we use the Azure DevOps REST API to disable the placeholder agent in that pool to ensure that they don't take requests.

```
agentPool="{%raw%}${{vars.AZDO_AGENT_POOL}}{%endraw%}"
agentName="{%raw%}${{env.HELM_RELEASE_NAME}}{%endraw%}-{%raw%}${{env.HELM_CHART_NAME}}{%endraw%}-placeholder"
echo "$agentName"

# Get the Pool Id based on the name
poolId=$(curl -f -s -u :{%raw%}${{secrets.AZDO_PAT}}{%endraw%} "{%raw%}${{secrets.AZDO_URL}}{%endraw%}/_apis/distributedtask/pools?poolName=$agentPool&api-version=7.1-preview.1" | jq ".value[0].id")
echo "pool id: $poolId"

sleep 5

# Get the first agent from the pool that matches our name
agentId=$(curl -f -s -u :{%raw%}${{secrets.AZDO_PAT}}{%endraw%} "{%raw%}${{secrets.AZDO_URL}}{%endraw%}/_apis/distributedtask/pools/$poolId/agents?api-version=7.1-preview.1" | jq -r ".value | map(select(.name == \"$agentName\")) | .[0] | .id")
echo "agentId id: $agentId"

# Disable the agent
curl -s -f -u :{%raw%}${{secrets.AZDO_PAT}}{%endraw%} -X PATCH -d "{ \"id\": \"$agentId\", \"enabled\": \"false\", \"status\": \"offline\"}" -H "Content-Type: application/json" "{%raw%}${{secrets.AZDO_URL}}{%endraw%}/_apis/distributedtask/pools/$poolId/agents/$agentId?api-version=7.1-preview.1"

```

## Step 5: Use the agents

To prove the agents were working I created the following pipeline in Azure Devops.  It outputs the azure CLI version and then sleeps for 10 seconds.

```
trigger: none

pool:
  name: KedaPool

steps:
  - bash: az --version
    displayName: Azure CLI version check
  
  - bash: sleep 10
    displayName: Sleep 10
```

The pool name `name: KedaPool` is the key bit for running against the self host agents.  (you may need to authorize the pipeline on first run).
Below is the agent poll with a number of pipeline runs in progress.

![Multiple agents running](/assets/2023-02-03/Multiple_agents_running.png)

*QUICK NOTE: The number of parallel runs is dictated by the number of Agents available (in our case limited by the resources on the cluster) AND the number of [parallel jobs available in Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops&tabs=ms-hosted).  This latter value tends to be the bigger restriction as it is a paid for resource.*




