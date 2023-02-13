---
layout: post
title: "Deploying and Configuring Nexus Repositories on AKS with Terraform"
date:   2023-02-09 10:00:00 +0100
categories: 
author: Matthew Fortunka
---


There are many options in Azure for storing application dependencies, for container/docker images you can use [Azure Container Registry](https://azure.microsoft.com/en-gb/products/container-registry/) and for development packages you can use [Azure DevOps Artifacts](https://learn.microsoft.com/en-gb/azure/devops/artifacts/start-using-azure-artifacts?view=azure-devops) (Nuget, npm, Maven or Python) or [Github Packages](https://github.com/features/packages) (Nuget, npm, Docker, Maven or RubyGems). Third Party products like [JFrog Artifactory](https://jfrog.com/artifactory/) or [SonaType Nexus Repository](https://www.sonatype.com/new/products/nexus-repository) offer alternative options if you are prepared to provision the virtual machines to run them.

Nexus has an [Open Source Implementation](https://github.com/sonatype/nexus-public), it runs as a Java 8 application and can be deployed to either Windows, Linux or OSX.   Alternatively, the app is packaged as a [Container Image](https://hub.docker.com/r/sonatype/nexus3/) which opens up the possibility of installing it on a container orchestration platform (like Azure Kubernetes Service), effectively giving you a private repository scoped to a cluster.

The following instructions detail a deployment of a Nexus OSS Repository to an Azure Kubernetes cluster using Terraform.

All the sample code can be found [here](https://github.com/fortunkam/nexus-aks-deploy).  The application can be deployed by running the terraform commands from the [infrastructure](https://github.com/fortunkam/nexus-aks-deploy/tree/main/infrastructure) folder.  Note: you will need to provide a different resource prefix (and possibly a different resource location) in the [dev.tfvars](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/variables/dev.tfvars) files.

```
terraform init
terraform apply -var-file "./variables/dev.tfvars" --var=nexus_admin_password="<SOMEPASSWORD>" --auto-approve
```

QUICK NOTE: This deploy will take over 10 minutes to run, a large part of this is the Nexus Repository starting up ready to be configured.

## Azure Resources

The following Azure resources are deployed as part of the deploy.

1. A [Resource Group](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/resourcegroup.tf) (**PREFIX-rg**)

    Technically two resource groups are created but one is managed by the AKS cluster. 

2. A [Storage Account](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/storage.tf) (**PREFIXstore**)

    This storage account is presented to the Nexus Repository as a file share.  All Nexus configuration is stored here.

3. An [Azure Container Registry](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/acr.tf) (**PREFIXacr**)

    The container registry is used to host an image used to initialize the repository.  In scenarios where the Nexus repository is exposed outside the cluster this could also be achieved using a terraform provisioner.
    
    Once the repository is deployed the nexus-initializer container image will be pushed to it using a combination of a `local-exec` provisioner and the `az acr build` command. (This means the machine running the terraform will also need the Azure CLI installed on it)

4. A [Public IP address](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/publicip.tf)

    This address is used by the Nexus Ingress to expose the repository outside of the cluster.  The public IP uses has a domain name which will be used by Lets Encrypt to generate the SSL certificate.

5. An [Azure Kubernetes Service cluster](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/aks.tf) (**PREFIX-aks**) 

    The AKS cluster is relatively simple, using kubenet networking and with a Managed Identity assigned.  The default node pool is larger (Standard_D8s_v5) than I would usually allocate for a demo cluster but [Nexus requires a minimum of 4 cpu (recommended 8) and a minimum of 8GB](https://help.sonatype.com/repomanager3/product-information/system-requirements#SystemRequirements-MemoryRequirements).

6. A [Role Assignment](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/aks.tf)

    In order for the Nginx Ingress controller to us the public IP in a resource group other than the one managed by AKS we need to grant permissions to the Managed Identity to that resource, see [here for a better explanation](https://stackoverflow.com/questions/56113146/azure-aks-public-ip-in-non-standard-resource-group). 


## Kubernetes Resources - Let's Encrypt

The Let's Encrypt helm chart is deployed to the cluster before the Nexus.  Let's Encrypt then handles the creation of certificates used to secure the Ingress IP.  Two Cluster Issuers are created as part of the Nexus deploy, one for generating staging certificates, the other for production. 

QUICK NOTE: Let's Encrypt have a [rate limiter for production certificates](https://letsencrypt.org/docs/duplicate-certificate-limit/).  The demo environment will use staging certificates, to change to production certificates set the value of the [certClusterIssuerSuffix](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/nexus.tf) to an empty string.

```
# Change

  set {
    name  = "ingress.nexus.certClusterIssuerSuffix"
    value = "-staging"
  }

# to 

  set {
    name  = "ingress.nexus.certClusterIssuerSuffix"
    value = ""
  }
```

## Kubernetes Resources - Nexus

The Nexus repository is installed and configured via a [helm chart](https://github.com/fortunkam/nexus-aks-deploy/tree/main/helm/nexus-repository).
The Helm chart deploys the following resources (all resources will be prefixed with the name of the helm deploy).

![Nexus Helm chart deployed resources diagram](/assets/2023-02-13/nexus-helm-resources.drawio.png)

### **\*-nexus-repository** [Deployment/ReplicaSet/Pod]

Manages a single instance of the Nexus Repository (limited to a single instance, will revisit for High Availability in the future).
The Pod has a persistent volume mounted to point at /nexus-data. 
The Pod exposes port 8081 which is the default Nexus administration endpoint.  

### **\*-nexus-repository-svc** [Service]

The Service handles the mapping of Port 8081 on the pod to Port 80.  The service would provide load balancing if more than one instance was running.

### **\*-nexus-repository-nexus-ingress** [Ingress]

The Ingress uses the Nginx controller (installed as a dependency of the chart) to expose the Nexus Repository to the outside work.  The endpoint is secured using the Let's Encrypt certificate.

QUICK NOTE: If you would like Nexus to act as a Docker Repository you will need an additional Ingress (and public IP, certicate etc.).  [Docker functionality is exposed on it's own port due to limitations of the docker API](https://blog.sonatype.com/using-nexus-3-as-your-repository-part-3-docker-images).

### **\*-nexus-repository-init-job** [Job]

This Job configures the Nexus Repository on first run.  The Job ensures the Nexus admin password is changed (to a value stored in a mounted secret) and the default repositories are removed (we will add them in later using Terraform). The basic flow is as follows (and is implemented in the [Init Container](https://github.com/fortunkam/nexus-aks-deploy/blob/main/src/nexus-initializer/configure_nexus.sh)).

![Nexus Initialization flow](/assets/2023-02-13/nexus-init-flow.drawio.png)

### **\*-nexus-repository-pvc** [Persistent Volume Claim]

The Nexus repository Pod and it's associated Initialization Job use a Persistent Volume mapped to an Azure Storage File Share.  In both cases the volume is mounted to /nexus-data, this is a standard folder used by Nexus to hold it's configuration data.

### **\*-nexus-repository-secret-init** [Secret]

Contains the username and password to be set on the Nexus repository when the Initializer job runs.

### **\*-nexus-repository-secret-storage** [Secret]

Contains the credentials for the Azure Storage account that is mounted as a persistent volume.

### **\*-nexus-repository-secret-docker** [Secret]

Contains the credentials for the Azure Container Registry that helm uses to pull the nexus-initializer container image.


## Nexus Configuration

Once the Nexus has been initialized (admin password reset and default repositories removed, configuration is done using the [Terraform Provider for Nexus](https://registry.terraform.io/providers/datadrivers/nexus/latest).

The [provider is initialized](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/providers.tf) using the admin credentials we set in the Kubernetes Job.

```
provider "nexus" {
  insecure = true
  password = var.nexus_admin_password
  url      = "https://${local.nexus_uri}"
  username = "admin"
}
```

The provider is configured with `insecure=true` this is to prevent the certificates from being checked when connecting. This is useful when using the Staging Let's Encrypt Issuer.

The URI used corresponds to the dns name given to the ingress public IP.

Once connected we can [disable anonymous access](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/nexus_config.tf).

```
resource "nexus_security_anonymous" "system" {
  enabled = false
  user_id = "anonymous"
  depends_on = [
    helm_release.nexus
  ]
}
```

or [add a private Nuget repository](https://github.com/fortunkam/nexus-aks-deploy/blob/main/infrastructure/nexus_config.tf) (or PyPI, npm, maven etc..)

```
resource "nexus_repository_nuget_hosted" "internal" {
  name   = "nuget-internal"
  online = true

  storage {
    blob_store_name                = "default"
    strict_content_type_validation = true
    write_policy                   = "ALLOW"
  }
  depends_on = [
    helm_release.nexus
  ]
}
```



