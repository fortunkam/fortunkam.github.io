---
layout: post
title:  "How to create Self Hosted Github runners using Terraform in Azure."
date:   2020-06-01 17:00:00 +0100
categories: GitHub Terraform
author: Matthew Fortunka
---
If you need to access network restricted resources from github actions you need to host your own runners within the network.  This post shows how to provision and install VMs to act as runners using Terraform.

The source for this article can be found here. [Repo](https://github.com/fortunkam/terraform-github-runners)

If you have ever used Self Host agents in Azure DevOps Pipelines the processs for setting up the VM is very similar.  Examples of setting up Pipeline agents can be found [here](https://github.com/fortunkam/aks-private-cluster-landing-zone).  (Note the solution creates agents as part of a private AKS cluster deploy) 

The Terraform script creates 2 different types of VM (Windows and Ubuntu) both are joined to a network.
Both the VMs use Managed Identity to access the deployment scripts.  Managed Identity creates and assigns an Azure Active Directory Service Principal to the VM that can be granted permissions to access resources.  [For more information on Managed Identity click here](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)


To run this script you will need to have the following installed.
- Terraform (at least v0.12.24, which what I used)
- Some command line interface (I have used either Powershell core v7 or Bash on Ubuntu 18.04 on WSL2)

Clone the repo (git clone https://github.com/fortunkam/terraform-github-runners.git)
Navigate to the folder in the CLI
Run 

    Terraform init

this will install the required modules
Now run,

    Terraform apply -auto-approve

You will be prompted for 2 pieces of information.
- Your GitHub Organisation name, this is the part of your github url after [https://github.com/](https://github.com/) (in my case for [https://github.com/fortunkam](https://github.com/fortunkam), fortunkam is the org name).  If you want to create your runner at a repo level (the only option for the free tier of github) then append the repo name to this e.g. fortunkam/repo
- Your Github Personal Access Token, this can be found by going to your organisation or repo, then settings, then Actions and "Add new runner" (Note: you might need to create  a workflow in the repo before it lets you do this).  The Token can be found after the --token parameter in the Configure script.

The key bits of work are done in the install scripts for each plaform ([Windows](https://github.com/fortunkam/terraform-github-runners/blob/master/env/scripts/configureWinRunner.ps1) and [Linux](https://github.com/fortunkam/terraform-github-runners/blob/master/env/scripts/configureLinuxRunner.sh))

The script 
- Creates a new folder
- Downloads and decompresses the required package (actions-runner)
- Configures the runner with the required parameters
- Starts the runner as a service.

If your runners require any additional bits of software installed on them they can be added to this script.
The beauty of the runner registration (and the Azure DevOps Pipelines Build agent equivalent). Is that the communications from the runner to GitHub is outbound (The runner polls Github for new work) which simiplifies the security requirements.

[For full details on GitHub runners see the official docs](https://help.github.com/en/actions/hosting-your-own-runners)











