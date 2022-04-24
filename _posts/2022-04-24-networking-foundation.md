---
layout: post
title: Networking Foundations
date: '2022-04-24'
categories: networking
excerpt_separator: <!--more-->
---

Welcome back to another post.
This time, we'll take a detour from OSX specific topics to talk about networking.
We want to make sure we understand the basics before we attempt to do anything fancy.
So here we'll post some RFCs you should read, compile some resources that explain what the hell the output from
tools such as `ifconfig` and `netstat` actually mean, etc etc.

<!--more-->


## Table of Contents
* TOC
{:toc}


## Terminology and the OSI Model

Check out
[An Introduction to Networking Terminology, Interfaces, and Protocols](https://www.digitalocean.com/community/tutorials/an-introduction-to-networking-terminology-interfaces-and-protocols).
This blog post provides some great background.

Couple things we want to repeat from that post
- A network device is software that serves as interface for networking hardware
  - In \*unix, network interfaces can be physical (real hardware) or virtual (linked to hardware but not actually hardware)
- MAC (medium access control) addresses are unique identifiers and are assigned to devices when they are manufactured.
  - MAC is a communication protocol of the link layer
- IP addresses are unique on each network
  - IP is implemented on top of the link layer, on the internet layer of the IP/TCP model
  - Networks can be linked if the traffic is properly routed (this is where NAT comes into place)
- ICMP is used for network devices to communicate amongst themselves to indicate availability or errors
- TCP builds upon IP to make reliable connections from unreliable packet transmissions by implementing "handshakes" (more on this later)

### IP

One of the first RFCs covering the IP protocol was
[RFS 791: INTERNET PROTOCOL](https://datatracker.ietf.org/doc/html/rfc791).

The important ideas from the RFC are that
- IP is meant to be unreliable - it favours simplicity so that other protocols can freely build upon it
- data is broken into packets where the actual data of interest, the payload, is sent with headers
  - headers communicate verious important metadata

### TCP

> The protocol builds up a connection prior to data transfer using a system called a three-way handshake.
> This is a way for the two ends of the communication to acknowledge the request and agree upon a method of ensuring data reliability.
>
> After the data has been sent, the connection is torn down using a similar four-way handshake.
xref:
[An Introduction to Networking Terminology, Interfaces, and Protocols](https://www.digitalocean.com/community/tutorials/an-introduction-to-networking-terminology-interfaces-and-protocols).

TCP follows similar conventions to IP, packets have a payload and headers.
An important piece of metadata is the TCP flag which identifies which type of TCP message is being sent.
These are the possible values

| Flag | Abbreviation | One letter abbreviation | Numerical value |
| ---- | ------------ | ----------------------- | --------------- |
| Urgent          | URG | U | 32 |
| Acknowledgement | ACK | A | 16 |
| Push            | PSH | P | 8  |
| Reset           | RST | R | 4  |
| Synchronization | SYN | S | 2  |
| Finish          | FIN | F | 0  |

Take a look at the following pages for more details
- [TCP flags](https://www.geeksforgeeks.org/tcp-flags/)
- [TCP Flags Explained](https://syedali.net/2014/12/29/tcp-flags-explained/)

Now, back to handshakes.
3 way handshake is used to establish a connection, [TCP 3 way handshake process](https://www.geeksforgeeks.org/tcp-3-way-handshake-process/)
1. Client sends SYN (S or 2)
2. Server responds with SYN-ACK (S-A or 18)
3. Client sends ACK (A or 16)

To terminate a connection, there is a [4-way handshake](https://wiki.wireshark.org/TCP-4-times-close.md)
1. Client sends FIN (0)
2. Server replies with ACK (16)
3. Server will close transmission and send FIN-ACK (16)
4. Client replies with ACK (16)


## CIDRS

You will see CIDRs and talk about masks so much and so often that we recommend you read through
- [Understanding IP Addresses, Subnets, and CIDR Notation for Networking](https://www.digitalocean.com/community/tutorials/understanding-ip-addresses-subnets-and-cidr-notation-for-networking)
- [Terraform `cidrsubnet` Deconstructed](http://blog.itsjustcode.net/blog/2017/11/18/terraform-cidrsubnet-deconstructed/)
  - Make sure to really look into the `ipcalc` examples here, it will make CIDRs make more sense.


## ifconfig

I don't know about you but like hell does `ifconfig` output make sense outright to me.
I did some research and came across
- [Demystifying ifconfig and network interfaces in Linux](https://codewithyury.com/demystifying-ifconfig-and-network-interfaces-in-linux/)
- [Monitoring the Interface Configuration With the ifconfig Command](https://docs.oracle.com/cd/E19253-01/816-4554/ipconfig-141/index.html)

Read them, digest them, and live by them.
And since we have a thing for all things OSX, also take a look at
- [Can someone please explain ifconfig output in Mac OS X?](https://superuser.com/questions/267660/can-someone-please-explain-ifconfig-output-in-mac-os-x/267669#267669)
- [What are these ifconfig interfaces on macOS](https://unix.stackexchange.com/questions/603506/what-are-these-ifconfig-interfaces-on-macos)

There is a lot more, so every now and them we'll come back and update this page.
