---
layout: post
title: Introduction to Ghidra
date: '2022-02-27'
categories: Reverse-Engineering
excerpt_separator: <!--more-->
---

Welcome back!
This is our first post about reverse engineering!
Because if we want to know how to defend, then we ought to know how to investigate.
The malware that is out there contains very important lessons and because of this, we will use this post as an introduction to reverse engineering.

In particular, we will cover [Ghidra](https://ghidra-sre.org/).
Why? Well, because Ghidra is very widely used, it is very damn useful, and it is free.
In later posts we’ll cover IDA, which is another damn good option for this type of work.

<!--more-->

## Table of Contents
* TOC
{:toc}

```dockerfile
FROM gradle:7.4-jdk11

ENV GHIDRA_SHA256 ac96fbdde7f754e0eb9ed51db020e77208cdb12cf58c08657a2ab87cb2694940
ENV GHIDRA_URL https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_10.1.2_build/ghidra_10.1.2_PUBLIC_20220125.zip

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 noroot
USER noroot
WORKDIR /home/noroot

# Download, check the checksum, and unzip Ghidra. Then we clean up.
RUN curl -L "${GHIDRA_URL}" > /tmp/ghidra.zip && \
    echo "${GHIDRA_SHA256} /tmp/ghidra.zip" | sha256sum -c - && \
    unzip /tmp/ghidra.zip && \
    mv ghidra_10.1.2_PUBLIC ~/ghidra && \
    chmod +x ~/ghidra/ghidraRun
```

```make
all: build
    docker run -it -p 8080:8080 ghidra bash

docs: build
    docker run -p 8080:8080 ghidra python3 -m http.server --bind 0.0.0.0 8080

build:
    docker build -t ghidra .
```
