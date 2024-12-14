---
layout: post
title: Setting Up a GitOps-Managed EKS Platform
date: '2024-12-14'
categories: [AWS, EKS, GitOps, Flux, Karpenter]
excerpt_separator: <!--more-->
---

Remember that time you deployed something to production and crossed your fingers hoping it would work? Or that sinking feeling when you realized your development environment was nothing like production? Well, I've been there too. That's why I embarked on this journey to build a Kubernetes platform that's both reliable and easy to work with (as much as possible).

In this post, I'll walk you through how to set up an EKS (Elastic Kubernetes Service) platform that manages itself using GitOps - which is basically letting Git be your source of truth instead of manually poking at servers and hoping for the best. Think of it as teaching your infrastructure to read and follow instructions, rather than having to hand-hold it through every change.

The secret sauce here is a combination of Flux (our GitOps conductor) and Karpenter (our infrastructure DJ who knows exactly when to spin up or down compute resources). It's like having a really efficient assistant who reads your Git commits and makes sure everything runs smoothly while also keeping an eye on costs.

**The code we'll discuss is in
[github.com/seafoodfry/bluesky-platform/infra](https://github.com/seafoodfry/bluesky-platform/tree/main/infra).**

<!--more-->

Why did I build this? Well, I needed a development and testing environment that wouldn't make me pull my hair out every time I needed to spin up a new cluster. Something robust enough to trust with real workloads, but not so complex that I'd need a PhD in cloud architecture to understand it. Plus, I wanted to document everything properly because future-me tends to forget what past-me was thinking.

Think of this setup as your Kubernetes happy place - where your infrastructure is version controlled, your deployments are automated, and your resources scale themselves. No more "works on my machine" syndrome, no more manual node scaling, and definitely no more midnight infrastructure emergencies (okay, maybe still some, but fewer!).

In this guide, I'll show you:
- How to set up this whole shebang from scratch
- The cool bits that make it work (and why they're cool)
- How to not blow your AWS budget in the process
- What to do when things inevitably go sideways

So grab your favorite beverage, fire up your terminal, and let's build something awesome together.



## Table of Contents
* TOC
{:toc}


---

## Requirements

This post will builds upon
[Setting Up an AWS Lab]({{ site.baseurl }}/aws/lab/2024/05/27/aws-lab-setup/)
in so much so that we assume you have a working IAM role that you can use to execute
AWS API calls.
We will use this foundation to outline a Terraform workspace to spin up GPU and non-GPU instances for graphics programming.

You can go ahead and continue reading, just be mindful that whenever we write things such as
```
./run-cmd-in-shell.sh aws sts get-caller-identity
```

The `./run-cmd-in-shell.sh` is a wrapper script we described in that previous post that allows us to run commands with a valid set of temporary IAM IAM role credentials.

Also keep in mind that our configurations are very 1Password centric since no one should be routinely having any sort of IAM user credentials in plain text or in a file on disk - but we also don't yet need to configure SSO access or anything of the sort.


---

## The Big Picture: How This Thing Works

Remember those Rube Goldberg machines where one thing triggers another in a perfectly choreographed sequence? Our EKS platform is kind of like that, but hopefully more reliable! Let me break down the key pieces:

### The Core Components

Picture this setup as a well-organized kitchen (stay with me here):

1. **The Kitchen Itself (EKS Cluster)**: This is our main workspace, with a dedicated prep area (managed node group) just for our essential tools like Flux and Karpenter. Think of it as having a special counter just for your most important kitchen gadgets.

2. **The Recipe Book (GitOps with Flux)**: Instead of keeping all our infrastructure recipes in our head (or worse, on random files we randomly apply in some way via `helm` or `kubectl`), we store everything in Git.
Flux is like our attentive sous chef who constantly reads these recipes and makes sure everything in our kitchen matches them exactly.

3. **The Smart Pantry System (Karpenter)**: Rather than manually restocking ingredients (compute resources), Karpenter automatically handles this for us. It knows when we need more resources and when we can put some back, saving us money and headache.


### How We Organized Everything

We took inspiration from the [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) repository.

1. **System Stuff** (`kube/infra/controllers`): This is where our core tools live. Think of it as the drawer with all your essential kitchen tools - your Karpenter, your monitoring systems, etc.

2. **Infrastructure Settings** (`kube/infra/configs`): These are the rules for how things should run, like your preferred cooking temperatures and times. This includes things like how Karpenter should provision new nodes.

3. **The Actual Applications** (`kube/apps/base` and `kube/apps/CLUSTER_NAME`): Finally, these are your actual recipes - the workloads that run on the cluster. We keep the basic recipes in `base` and any special modifications for specific "kitchens" (clusters) in their own folders.

### Why This Setup Makes Sense

The beauty of this organization is that everything happens in the right order - just like you wouldn't start plating your food before the cooking is done. When the cluster starts up:

1. First, all the essential tools get installed (your knife set and cutting boards, if you will)
2. Then, the infrastructure rules get applied (setting up your workspace)
3. Finally, your actual applications can start running (time to cook!)

This means no more "but it worked in dev!" problems, because every environment follows the exact same setup process, just with different settings where needed.

And the best part? When you want to make a change, you just update the relevant files in Git, and Flux makes sure everything gets updated properly. No more SSHing into servers at 3 AM trying to remember what you changed last week!



---

## Behind the Engineering: Key Decisions and Implementations

After covering the high-level architecture, let's dig into the actual engineering decisions that make this platform work. The complete code is available in [github.com/seafoodfry/bluesky-platform/infra](https://github.com/seafoodfry/bluesky-platform/tree/main/infra), and there's also a detailed design document at
[github.com/seafoodfry/bluesky-platform/docs/designs/001-eks](https://github.com/seafoodfry/bluesky-platform/tree/main/docs/designs/001-eks)
that explains our thinking process and technical decisions in depth.

You can also read the README for the infrastructure over at
[github.com/seafoodfry/bluesky-platform/infra](https://github.com/seafoodfry/bluesky-platform/tree/main/infra).
It will fill in how we create and destroy everything needed for this platform.
It also includes example Cloudwatch Log Insight quereis, handy `kubectl` commands to debug Flux and Karpenter., and many other gems.

### The Challenge of Idempotent GitOps

One of the first challenges we faced was implementing GitOps in a truly idempotent manner. When bootstrapping a new environment, we discovered that simply adding YAMLs and HelmReleases to a directory for Flux to apply doesn't guarantee success. For example, we encountered synchronization failures when trying to configure Karpenter NodePool resources before their required Custom Resource Definitions were available. 

This experience taught us that we needed to carefully structure our GitOps resources to respect dependencies. The solution came from studying the [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) repository, which outlines a pattern for separating resources based on their dependencies.

### The Core and The Edge

Our implementation divides workloads into three distinct categories:

1. Core cluster controllers in `kube/infra/controllers`
2. Infrastructure configurations in `kube/infra/configs`
3. Application workloads in `kube/apps/base` and their cluster-specific patches

This separation isn't just organizational - it's crucial for reliability. The core controllers (like Karpenter) must be installed before any resources that depend on them (like EC2NodeClasses). By structuring our GitOps configuration this way, we ensure that resources are applied in the correct order, making the system truly idempotent.

### Security Through IAM

A significant design choice was moving away from the configmap-based authentication that allows unauthenticated users to make Kubernetes API calls. Instead, we exclusively use IAM authentication via the "API" EKS configuration method.
This means every identity accessing the cluster is explicitly managed through AWS IAM, making our security posture both stronger and more auditable.

### Debugging with CloudTrail

Instead of wrestling with permissions issues through trial and error, we integrated CloudTrail with CloudWatch Logs. This gives us powerful querying capabilities through CloudWatch Log Insights. We've found this setup invaluable for debugging issues, particularly with Pod Identity and SQS permissions for Karpenter's spot instance interruption handling.


## Final Thoughts

We continue to evolve this platform as we learn more, and we're particularly interested in:
- Expanding our workload patterns
- Improving our development workflows
- Adding more observability tools

If you try this out or have suggestions for improvements, we'd love to hear about your experience. Infrastructure should be a joy to work with, not a source of stress, and we hope this platform helps move us in that direction.