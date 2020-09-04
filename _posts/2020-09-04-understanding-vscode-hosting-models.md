---
layout: post
title:  "Understanding the VSCode hosting models."
date:   2020-09-4 10:00:00 +0100
categories: VSCode WSL
author: Matthew Fortunka
---

I spend a lot of my day in VSCode, it has replaced "full-fat" Visual Studio for small projects (although I still prefer it for .net development) and has superceded the notepad/notepad++'s of the world for general quick editing.  (This blob post is being written in markdown in vscode for example).  Over the last year the options for how you run vscode have become numerous and need a little explaining so lets start with how the application is structured.

VSCode consists of 2 parts, a client, which handles to drawing to the screen (and things like themes), and the server which handles everything else (your file system, the debugger, terminal etc)

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-local-server-local.png "vscode local client and server")

On Windows when you open a folder in vscode (or use `code .` from a terminal) you are running both the client and the server on the same OS.

Now the fun begins, if you are running the Windows Subsystem for Linux (and frankly you should be).  If you run open a folder in vscode that exists in the Linux Filesystem you are starting up the 2 parts of VSCode in different places.  The client runs on windows as normal but the server runs on WSL, hence why you see a bash termial as the default.

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-local-server-wsl.png "vscode local client and server in WSL")

Lets take this a step further, since we know the server will run on linux how about we run in on a different machine using an SSH tunnel to connect the client and the server.  This is made possible thanks to the [Remote Development Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) from the marketplace.

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-local-server-remote.png "vscode local client and server on remote linux machine")

So now how about instead of running in a full fat Linux machine we run the server component in a container.  The beauty of this solution is that the container definition can live inside your repo and vscode will detect that a dev container is present and prompt you to open the solution using it.  [For more information on devcontainers see here](https://code.visualstudio.com/docs/remote/containers-tutorial).  Running in a container has an advantage in that everyone that clones your repo is working with exactly the same version of tools that you used initially.  In case you were wondering VSCode presents the local file system where the source code is stored as a volume to the container.  

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-local-server-container.png "vscode local client and server on dev container")

Now that our vscode server is wrapped in a container, why not have that container hosted in the cloud and connect to them from your local VSCode client?  [Visual Studio Codespaces](https://docs.microsoft.com/en-gb/visualstudio/codespaces/overview/what-is-vsonline) is the answer to that question. containers are created in Azure (along with some storage space to provide you with a file system) and you pay while they are running (it will even suspend them after a period of inactivity so you don't run up a huge bill)

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-local-server-codespace.png "vscode local client and server on codespace")

Finally, this just leaves the VSCode client, which with codespaces is now just a "lightweight" electron app running on your local machine relaying requests to the server, do we need it at all.   Turns out, no, with codespaces they have provided a browser implementation of the client.  

![](/assets/2020-09-04-understanding-vscode-hosting-models/VSCode-client-browser-server-codespace.png "vscode browser client and server on codespace")





