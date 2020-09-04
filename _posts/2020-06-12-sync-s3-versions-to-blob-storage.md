---
layout: post
title:  "How to sync AWS S3 files to Azure blob versioning."
date:   2020-06-12 12:00:00 +0100
categories: Blob S3 Powershell
author: Matthew Fortunka
---

*** This article was originally written about the preview of Blob versioning, the feature was made generally avaialble in September 2020 ***

AWS S3 buckets have a concept of versioning files, until recently there has been no equivalent of this in Azure and people have needed to put workarounds in place to "replicate" this functionality.  As of September 2020, Azure released [Blob Versioning](https://docs.microsoft.com/en-us/azure/storage/blobs/versioning-overview?tabs=powershell).  When enabled every time an update operation occurs on a blob a new version is created.  Each version can then be retrieved independently.

Now there are equivalent services in AWS and Azure, it is useful to be able to migrate content from one to the other.  To that end I have created a couple of powershell scripts.

[The first populates an existing S3 bucket with sample files, each file has multiple versions assoicated with it](https://github.com/fortunkam/aws_s3_to_blob_version_sync/blob/master/generate_random_s3_content.ps1)

[The second migrates files from S3 to a blob storage account with versioning enabled](https://github.com/fortunkam/aws_s3_to_blob_version_sync/blob/master/blob_sync.ps1)

Each blob version is tagged with the equivalent AWS version id (there is no control over the blob version id that is allocated).  

When a blob is uploaded to a storage account the version id is returned in the `x-ms-version-id` header.

Specific blob versions can be retrieved from storage by making a get request and passing the version id in with it (you will need to pass access tokens as described [here](https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-requests-to-azure-storage)).

    https://$azureBlobStorageName.blob.core.windows.net/$azureBlobContainerName/$localFileName?versionId=$someversionId
