---
layout: post
title: "Deploying API Management APIs using Github Actions - Part 1"
date:   2021-09-14 10:00:00 +0100
categories: 
author: Matthew Fortunka
---

You may have noticed a theme around API management recently, I spend a lot of time talking to people about this product and like to share the patterns I see in the wild.
I split this post up into 2 parts, we will begin with understanding the process before moving on to Part 2 where we will create the github actions.

DevOps (particularly CI and CD) with API Management is a challenging problem to solve,  the majority of work done configuring APIM APIs is done in the portal compared with the backend APIs which tend to be code-first. Ultimately the APIM APIs are just ARM templates so if you want to create them by hand you can however the APIM team have an toolkit called the [Azure API Management DevOps Resource Kit](https://github.com/Azure/azure-api-management-devops-resource-kit) to help with these challenges.

The toolkit solves the CI/CD problem in one of two ways.

1. For developers who do all their work in a non-prod APIM instance and want to copy some or all of the configuration to another instance, there is a tool called `extract` that generates parameterised ARM templates from one APIM instance.  These can then be applied to another APIM instance.
2. For developers who want to start as code, there is a tool called `creator`.  In this scenario the developer has an openid/swagger definition stored in a repo, along with some policy xml files.  They create a configuration file for the tool which will generate the ARM templates.  This is the one we are going to dig into a little further.

The code for the setup below can all be found at [this repository](https://github.com/fortunkam/apim_api_demo) and makes use of the wonderful [ICanHazDadJoke api](https://icanhazdadjoke.com/api).


In this scenario we have a third-party API and want to add this to APIM.  Along the way we want to change how some of the APIs are called.  We are going to expose 2 operations.

1. **Get a Single Joke**  This will be available as a GET request and takes no parameters.  The underlying API is also a GET request and takes no parameters.
2. **Search for Jokes**  This will be available as a POST request and has a body payload.  The underlying API is a GET request with query string parameters, so we are going to need to use APIM Policies to change the API.

We have a swagger file (OpenAPI 3.0 yaml) for this api that can be [found here.](https://github.com/fortunkam/apim_api_demo/blob/main/swagger/icanhazdadjoke.yml)


The `creator` tool takes a yaml configuration file and at its simplest we define a single API and Backend.

```
apimServiceName: mfapim
apis:
- description: ICanHazDadJoke APIM Wrapper
  displayName: ICanHazDadJoke
  name: ICanHazDadJoke
  openApiSpec: ./swagger/icanhazdadjoke.yml
  openApiSpecFormat: OpenApi30_Yaml
  serviceUrl: https://icanhazdadjoke.com
  suffix: dadjoke
outputLocation: .\templates
version: 0.0.1
```

If we run the creator tool (I am running it from source but it can be installed as a dotnet global tool)

`dotnet run create --configFile api1.yaml --project "$path_to_source\apimtemplate.csproj" -c "Release"`

It will generate an ARM template (and a parameters file) that can then be deployed to a target apim using the following command.

`az deployment group create -g "<RESOURCE_GROUP_NAME>" --template-file ".\templates\ICanHazDadJoke.api.template.json" --parameters ApimServiceName=<APIM_NAME> ICanHazDadJoke-ServiceUrl=<BASE_URL>`

As a refinement you might want to break out the serviceUrl into a backend API.

```
apimServiceName: mfapim
apis:
- description: ICanHazDadJoke APIM Wrapper
  displayName: ICanHazDadJoke
  name: ICanHazDadJoke
  openApiSpec: ./swagger/icanhazdadjoke.yml
  openApiSpecFormat: OpenApi30_Yaml
  policy: policies/icanhazdadjoke.xml
  suffix: dadjoke
backends:
- title: ICanHazDadJoke
  description: ICanHazDadJoke API
  url: https://icanhazdadjoke.com
  protocol: http
outputLocation: .\templates
version: 0.0.1
```

A couple of things to point out, the first is Backend section, the second is the addition of a policy xml file.
This [policy](https://github.com/fortunkam/apim_api_demo/blob/main/policies/icanhazdadjoke.xml) is applied to all APIs and sets the backend to point at our newly created resource (and also enforces that the accept header is sent correctly with every request)

```
<policies>
    <inbound>
        <set-backend-service backend-id="ICanHazDadJoke" />
        <set-header name="Accept" exists-action="override">
            <value>application/json</value>
        </set-header>
        <base />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

When you rerun the create tool this now generates 2 ARM templates, one for the API and one for the Backend.  When you deploy these it is important to deploy them in the right order, so backend first, then API.

Finally lets add the configuration policies for the individual operations, here is our yaml..

```
apimServiceName: mfapim
apis:
- description: ICanHazDadJoke APIM Wrapper
  displayName: ICanHazDadJoke
  name: ICanHazDadJoke
  openApiSpec: ./swagger/icanhazdadjoke.yml
  openApiSpecFormat: OpenApi30_Yaml
  policy: policies/icanhazdadjoke.xml
  suffix: dadjoke
  subscriptionRequired: true
  operations:
    getRandomJoke:
      policy: policies/singleJoke.xml
    searchForJokes:
      policy: policies/searchJokes.xml
  products: unlimited
backends:
- title: ICanHazDadJoke
  description: ICanHazDadJoke API
  url: https://icanhazdadjoke.com
  protocol: http
outputLocation: .\templates
version: 0.0.1
```

and we have 2 new policy files added ([singleJoke.xml](https://github.com/fortunkam/apim_api_demo/blob/main/policies/singleJoke.xml) and [searchJokes.xml](https://github.com/fortunkam/apim_api_demo/blob/main/policies/searchJokes.xml)).  singleJoke.xml just contains the default empty policy but searchJokes.xml is a bit more involved.

```
<policies>
    <inbound>
        <set-query-parameter name="term" exists-action="override">
            <value>@(context.Request.Body.As<JObject>(preserveContent:true).Value<string>("term"))</value>
        </set-query-parameter>
        <set-query-parameter name="page" exists-action="override">
            <value>@(context.Request.Body.As<JObject>(preserveContent:true).Value<string>("page"))</value>
        </set-query-parameter>
        <set-query-parameter name="limit" exists-action="override">
            <value>@(context.Request.Body.As<JObject>(preserveContent:true).Value<string>("limit"))</value>
        </set-query-parameter>
        <set-method>GET</set-method>
        <base />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Our APIM API passes in parameters in the POST body but our backend API expects them as Query string parameters so we need to map them.  The backend api is also expecting a GET request so we need to change that over too.

So now locally we have a collection of 5 files that can be used to generate the ARM templates for our API.  In the next part we will look at recreating this process in Github actions.