---
layout: post
title: Setting Up a GitOps-Managed EKS Platform
date: '2024-12-14'
categories: [AWS, EKS, GitOps, Flux, Karpenter]
excerpt_separator: <!--more-->
---

Hi all, this time we wanted to make a post on a sample platform we have been building over in our project
[github.com/seafoodfry/bluesky-platform](https://github.com/seafoodfry/bluesky-platform).

Here we designed a thing for us to do some R&D, development, and to run some apps.
This platform is built from an EKS cluster that can only be accessed through an IP allow list,
and that maps RBAC permissions directly to IAM roles - getting rid of the `aws-auth` configmap.

Along with that, the EKS cluster has a single managed node group where [Flux](https://fluxcd.io/)
bootstraps [karpenter](https://karpenter.sh/) for node management.
This way we can have all workloads managed by Flux with GitOps - simplifying the delivery part of CICD -
and we can have karpenter to scale our cluster quickly and in the most economic manner. 

The complete code is available in
[github.com/seafoodfry/bluesky-platform/infra](https://github.com/seafoodfry/bluesky-platform/tree/main/infra).
There is also a design document at
[github.com/seafoodfry/bluesky-platform/docs/designs/001-eks](https://github.com/seafoodfry/bluesky-platform/tree/main/docs/designs/001-eks)
that explains our thinking process and technical decisions in depth.

We also documented how we are using the platform over at
[github.com/seafoodfry/bluesky-platform/infra](https://github.com/seafoodfry/bluesky-platform/tree/main/infra).
It outlines how we create and destroy everything needed for this platform.
It also includes example Cloudwatch Log Insight quereis, handy `kubectl` commands to debug Flux and Karpenter, and many other things.

<!--more-->

Before we proceed let's briefly talk over some things.

Kubernetes is a very reliable and relatively cheap platform.
It allows for a standardize way of running things in research, development, and production.
We have been maintaining of research environment over at
[github.com/seafoodfry/ml-workspace/gpu-sandbox](https://github.com/seafoodfry/ml-workspace/tree/main/gpu-sandbox) - and we will continue to do so - but sometimes we need a more "real life" environment
where we can provision and orchestrate multiple apps and infra resources.

Then comes the [Flux](https://fluxcd.io/) part.
Most people will use Jenkins or GitLab.
But with a tad better UX come GitHub Actions.
But they "push" data to a cluster.
GitOps is a different model where we can have a controller "pulling" from a Git repo.
And on top of that, Flux can manage Helm chart, kustomize, and plain YAML all via its different CustomResources.
So it unifies all the ways of deploying applications and it ensures that everything looks the way you want it, constantly.

Then it came karpenter.
If you are like me, you may still be hooked into the cluster autoscaler, but it just so happens that technology has advanced a good deal since we were deploying that thing on mass.
Karpenter is faster to scale up and down a cluster, and it is more flexible because it can figure out a good and descent EC2 given any workloads that are pending. (And its super simple to request spot instances!)


## Table of Contents
* TOC
{:toc}


---

## Requirements

This post builds upon
[Setting Up an AWS Lab]({{ site.baseurl }}/aws/lab/2024/05/27/aws-lab-setup/).
We assume that you have a similar configuration in such a way that you can readily get a temporary set of credentials for an IAM role in a manner similar to our `./run-cmd-in-shell.sh` wrapper script.

We also assume that any you'll understand when we say that we stored all the secrets necessary to manage our platform in a 1Password vault and are using the
[`op` CLI](https://developer.1password.com/docs/cli/get-started/)
to use these values.

In
[Setting Up an AWS Lab for Graphics Programming]({{ site.baseurl }}/aws/lab/gpu/graphics/2024/06/21/graphics-pt-01/)
we also introduced the `tfenv` CLI, but let's copy-paste that bit here too:
[github.com/tfutils/tfenv](https://github.com/tfutils/tfenv)
is our recommended way to manage the Terraform versions you will need.

For this example we did
```
tfenv init
tfenv install 1.8.4
tfenv use 1.8.4
```

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

## Behind the Engineering

### Why Kustomize?

Kustomize can be complex as it supports a ton of stuffs.
See
[github.com/kubernetes-sigs/kustomize/examples](https://github.com/kubernetes-sigs/kustomize/tree/master/examples).

But the Helm templating language is hella worse.

And the cool thing with Flux is that it relies on kustomize, so it is harder to get your
deployment artifacts out of control.
And anytime we deal with plain YAML (even it if was kustomized), you avoid the chances of running into
troubles because Helm was managing some field in someway and someone manually modifed it at some point.

And you can still install Helm charts with Flux, so all is good.

### The Challenge of Idempotent GitOps

One of the first challenges we faced was implementing GitOps in a truly idempotent manner. When bootstrapping a new environment, we discovered that simply adding YAMLs and HelmReleases to a directory for Flux to apply doesn't guarantee success. For example, we encountered synchronization failures when trying to configure Karpenter NodePool resources before their required Custom Resource Definitions were available. 

This experience taught us that we needed to carefully structure our GitOps resources to respect dependencies. The solution came from studying the [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) repository, which outlines a pattern for separating resources based on their dependencies.



---

## Other Useful Bits

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
