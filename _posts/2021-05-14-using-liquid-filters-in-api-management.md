---
layout: post
title:  "Using Liquid filters in Azure API Management."
date:   2021-05-14 10:00:00 +0100
categories: Azure APIM
author: Matthew Fortunka
---

API Management is a great tool for "fronting" your companies APIs and has some powerful tools to shape and transform those operations.  One such tool is the `set-body` policy.  This policy lets you shape either the request sent to the backend (if placed in the `<inbound>` element) or the response sent to the client (if called in the `<outbound>` section).
The policy works in one of 2 ways, using code snippets (C# with a subset of the .net framework) or using [liquid templates](https://shopify.github.io/liquid/basics/introduction/).  The code snippets are great for minor modifications (e.g. remove or add a property to the existing body) but liquid templates give you an editor experience that is closer to the expected output.

At a high level, lets assume I want to call the [ICanHazDadJoke API](https://icanhazdadjoke.com/api).  (I am a sucker for terrible joke!)
The search api

    GET https://icanhazdadjoke.com/search?term=cat
    Accept: application/json

will return the following json payload (truncated results)..

    {
        "current_page": 1,
        "limit": 8,
        "next_page": 2,
        "previous_page": 1,
        "results": [
            {
            "id": "O7haxA5Tfxc",
            "joke": "Where do cats write notes?\r\nScratch Paper!"
            },
            {
            "id": "TS0gFlqr4ob",
            "joke": "What do you call a group of disorganized cats? A cat-tastrophe."
            }
        ],
        "search_term": "cat",
        "status": 200,
        "total_jokes": 10,
        "total_pages": 2
    }

I have created a new API Operation in APIM and configured the backend to point at icanhazdadjoke.com.

lets assume instead of returning this object we just want to return a json array of the jokes.  We can do this with a `set-body` policy in APIM (inside the `<outbound>` section).

{% raw %}
    <set-body template="liquid">{
        "results": [
            {% JSONArrayFor joke in body.results %}
                "{{ joke.joke }}"
            {% endJSONArrayFor %}
        ]
    }</set-body>
{% endraw %}

We are using `JSONArrayFor` here instead of `for` to ensure no trailing comma is left.
My API call now returns something like this...

    {
        "results": [
                      
                "Where do cats write notes?
    Scratch Paper!",
            
                "What do you call a group of disorganized cats? A cat-tastrophe." 
        ]
    }

Almost there, but when I try to test this using the excellent rest-client extension in VSCode, it complains that the body isn't a valid JSON payload!  The reason is the rogue `\r\n` in the first joke, so we need to strip out/convert any newlines before we return the response.  Enter [liquid filters](https://shopify.github.io/liquid/filters/newline_to_br/)! 

According to the documentation I should be able to change my `set-body` policy to use one or more filters like this (I am using both to really make sure they are gone 😀, actually newline_to_br adds a br element in front of any \r\n but we still need to get rid of them, this way the intended formatting is preserved as html)..

    {% raw %}
    <set-body template="liquid">{
        "results": [
            {% JSONArrayFor joke in body.results %}
                "{{ joke.joke | newline_to_br | strip_newlines }}"
            {% endJSONArrayFor %}
        ]
    }</set-body>
    {% endraw %}

Run this through APIM and there is no change to the output!  How odd!
Some more  reveals some odd truths, the implementation of liquid in APIM is based on the [dotliquid](https://github.com/dotliquid/dotliquid) library ([source](https://azure.microsoft.com/en-gb/blog/deep-dive-on-set-body-policy/?ref=msdn)).  Nestled amongst the documentation for dotliquid is a reference to [Filter and Output Casing](https://github.com/dotliquid/dotliquid/wiki/DotLiquid-for-Designers#filter-and-output-casing), which states that 

"DotLiquid uses this same convention by default, but can also be changed to use C# naming convention, in which case output fields and filters would be referenced like so {{ SomeField | Escape }}"

hmmm, I wonder if the C# naming convention is the default for APIM, if so then the following `set-body` policy should work..

    {% raw %}
    <set-body template="liquid">{
        "results": [
            {% JSONArrayFor joke in body.results %}
                "{{ joke.joke | NewlineToBr | StripNewlines }}"
            {% endJSONArrayFor %}
        ]
    }</set-body>
    {% endraw %}

🎉ta-da🎉 valid json.

    {
        "results": [
            "Where do cats write notes?<br />Scratch Paper!",
            "What do you call a group of disorganized cats? A cat-tastrophe."
        ]
    }

