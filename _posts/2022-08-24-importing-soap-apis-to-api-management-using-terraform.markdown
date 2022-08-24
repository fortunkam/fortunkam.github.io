---
layout: post
title: "Importing SOAP APIs to API Management using Terraform"
date:   2022-08-24 08:00:00 +0100
categories: 
author: Matthew Fortunka
---
How to handle deployments of APIs into API Management is something I have spoken about (see [here](https://docs.microsoft.com/en-us/shows/lunchbytes/devops-api-management)) and written about ([see here]({% post_url 2021-09-14-deploying-api-management-apis-using-github-actions %}) and [here]({% post_url 2021-09-14-deploying-api-management-apis-using-github-actions-part-2 %})) a bit before.  Typically I use examples of loading a REST API by importing the OpenAPI or Swagger file and augumenting it with API Managements own policies.  However, there are still a lot of XML/SOAP based APIs out there and API Management definitely has a place in modernising and protecting these systems.

If you import a SOAP API (using the WSDL file) into API Management via the Azure Portal you will see the following options.

![](/assets/2022-08-24-importing-soap-apis-to-api-management-using-terraform/import-wsdl.png "Import WSDL file option")

![](/assets/2022-08-24-importing-soap-apis-to-api-management-using-terraform/import-wsdl-form.png "Import WSDL form")

The form shows there are 2 ways to import the WSDL file.

* From a file on your local machine
* From an accessible URL

API Management will then generate an API wrapper around those operations in one of 2 ways.

* SOAP pass-through - SOAP Requests arrive at API Management and are proxied through to the backend service (everything stays as XML throughout)
* SOAP to REST - Requests arrive at API Management as JSON, API Management policies convert the JSON to SOAP, send to the backend and then convert the response back to JSON.

You can achieve all the same results by generating your API in Terraform (For reference Bicep works similar).  

This is our basic Terraform API definition
```
data "azurerm_api_management" "apim" {
  name                = local.apimName
  resource_group_name = local.resource_group_name
}

resource "azurerm_api_management_api" "my_api" {
  name                = "my-soap-api"
  resource_group_name = local.resource_group_name
  api_management_name = data.azurerm_api_management.apim.name
  display_name        = "My API"
  revision            = "1"
  protocols           = ["https"]
  path                = "my-soap-api"  
  service_url         = "https://my-api-base-url.azurewebsites.net"
}
```

We get a reference to our local APIM instance (so that it can be deployed independently of the APIs) and we set up the basic options common to every API (name, path, base url etc).

Now lets import the WSDL file, for this we need to use the import section..


```
 import {
    content_format = "wsdl-link"
    content_value  = "https://my-api-base-url.azurewebsites.net/MyService.svc?wsdl"
    wsdl_selector {
      service_name = "MyService"
      endpoint_name = "BasicHttpsBinding_IMyService"
    }
  }
```

Lets break down what these options, first **content_format = wsdl-link** tells the import section to expect a URL to the WSDL file instead of the xml.  **content_value** is the WSDL URL.  The **wsdl_selector** section lets you decide which Service defined in the WSDL you would like to import.  So in my case my WSDL looks like the following...

![](/assets/2022-08-24-importing-soap-apis-to-api-management-using-terraform/wsdl_fragment.png "Import WSDL form")

Similarly, if I want to import from a file, **wsdl-link** changes to **wsdl** and we make use of terraforms *file* function, like so..

```
 import {
    content_format = "wsdl"
    content_value  = file("./localwsdl.xml")
    wsdl_selector {
      service_name = "MyService"
      endpoint_name = "BasicHttpsBinding_IMyService"
    }
  }
```

In both of these cases, API Management will create an API that translates your SOAP API to REST.  If you want to do a SOAP pass through API, there is a single property that needs to be set before the import section.

```
  soap_pass_through   = true
```

So for a complete example, here is an API imported from a local WSDL file that accepts a SOAP request and forwards it onto the backend service.

```
resource "azurerm_api_management_api" "my_api" {
  name                = "my-soap-api"
  resource_group_name = local.resource_group_name
  api_management_name = data.azurerm_api_management.apim.name
  display_name        = "My API"
  revision            = "1"
  protocols           = ["https"]
  path                = "my-soap-api"  
  service_url         = "https://my-api-base-url.azurewebsites.net"
  soap_pass_through   = true
  import {
    content_format = "wsdl"
    content_value  = file("./localwsdl.xml")
    wsdl_selector {
      service_name = "MyService"
      endpoint_name = "BasicHttpsBinding_IMyService"
    }
  }
}
```

The api can then be deployed using the usual `terraform plan|apply` commands.

As always, more complete examples can be found on my [github](https://github.com/fortunkam/apim-terraform-soap-import)


