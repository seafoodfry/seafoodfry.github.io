---
layout: post
title: Setting Up an AWS Lab
date: '2022-06-12'
categories: [AWS, lab]
excerpt_separator: <!--more-->
---

This post will cover how to set up a lab in AWS.
Why AWS? Because it is the platform with the most users, which means that it is more likely that
some of this will be applicable to other things you may do.
Why a lab? Because you may not want to buy multiple Windows, Mac, or Linux machines running amd64 or arm64 (and maintain them).

<!--more-->


## Table of Contents
* TOC
{:toc}

---

## Roadmap

Let's assume for now that you have already signed up for an AWS account and that you configured some good MFA for you root account.
In the following sections we will cover how to do the following

1. configure our account so we can begin using it
1. install the tooling we need to work with our AWS account
1. set up our first ec2 and go over some useful documentation


**Note:** what we are about to cover is a set of recommendations for how to keep a personal AWS lab secure. This is not the same
as setting up an account for an organization. For an organization you want to make use of AWS organizations to manage multiple AWS
accounts and you should use SSO instead of creating IAM users.

---

## Seting Up IAM Permissions

The goal is to create IAM groups that allow IAM users in their group to assume IAM roles.
Assuming roles is the AWS recommended way for users and services to send AWS API request.
Why? Because when you assume a role, you get a set of temporary credentials, which is more secure than long-term static credentials.
Plus, you can enforce MFA usage when a user attempts to assume a role.

### Create an IAM Policy for MFA Management

The whole point of this set up is to enforce MFA.
To do this properly, we need to create an IAM policy, which we will later associate with your IAM group, along with the Administrator or the PowerUserAccess policies.
This policy is elaborate but we will copy-paste it from
[AWS: Allows MFA-authenticated IAM users to manage their own credentials on the My Security Credentials page](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_my-sec-creds-self-manage.html).
However, we will do some modifications and use the following version (we only care about access keys and MFA).
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowViewAccountInfo",
            "Effect": "Allow",
            "Action": [
                "iam:ListVirtualMFADevices"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowManageOwnPasswords",
            "Effect": "Allow",
            "Action": [
                "iam:ChangePassword",
                "iam:GetUser"
            ],
            "Resource": "arn:aws:iam::*:user/${aws:username}"
        },
        {
            "Sid": "AllowManageOwnAccessKeys",
            "Effect": "Allow",
            "Action": [
                "iam:CreateAccessKey",
                "iam:DeleteAccessKey",
                "iam:ListAccessKeys",
                "iam:UpdateAccessKey"
            ],
            "Resource": "arn:aws:iam::*:user/${aws:username}"
        },
        {
            "Sid": "AllowManageOwnVirtualMFADevice",
            "Effect": "Allow",
            "Action": [
                "iam:CreateVirtualMFADevice",
                "iam:DeleteVirtualMFADevice"
            ],
            "Resource": "arn:aws:iam::*:mfa/${aws:username}"
        },
        {
            "Sid": "AllowManageOwnUserMFA",
            "Effect": "Allow",
            "Action": [
                "iam:DeactivateMFADevice",
                "iam:EnableMFADevice",
                "iam:ListMFADevices",
                "iam:ResyncMFADevice"
            ],
            "Resource": "arn:aws:iam::*:user/${aws:username}"
        },
        {
            "Sid": "DenyAllExceptListedIfNoMFA",
            "Effect": "Deny",
            "NotAction": [
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:GetUser",
                "iam:ListMFADevices",
                "iam:ListVirtualMFADevices",
                "iam:ResyncMFADevice",
                "sts:GetSessionToken"
            ],
            "Resource": "*",
            "Condition": {
                "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                }
            }
        }
    ]
}
```

Now,
1. Go to the "IAM Services" dashboard.
1. On the left-hand sidebar, click "Policies".
1. Click "Create Policy", button may be on top-right.
1. Click the "JSON" tab and copy paste the IAM policy document.
1. Click "Next: Tags".
1. Click "Next: Review".
1. Provide a name and a description for your policy, review it. If everything look alright, click "Create Policy".

We will attach this policy to the group we will create later on.
That way user's will be able to manage their credentials and MFA properly.

### Assumable IAM Roles

Because we definetely want to enforce MFA use, we want to only allow members of a group permissions when they assume a role.
So we first need to create roles that are meant to be assumed and give them the permissions we desired.

1. Go to the "IAM Services" dashboard.
2. Click on "Roles" on the left-side bar.
3. Click "Create Role", the button will be on the right-hand side.
4. For "Trusted entity type", select "Custom trust policy". The policy you want should look a tad like this (change the AWS account ID), it will allow resources in you account to assume it
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::123456789012:root"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession",
                "sts:SetSourceIdentity"
            ]
        }
    ]
}
```
5. Click "Next".
6. Select the IAM policy you want to attach to your IAM role, either `arn:aws:iam::aws:policy/AdministratorAccess` or `arn:aws:iam::aws:policy/PowerUserAccess`.
7. Click "Next" and then you'll be able to name your group and provide a description.
8. Click "Create Role".

**Note:** before you go, click on the IAM role you just created. When you do so, you will see a summary page. On it, note that there is a
"Link to switch roles in console", save it, you will need it later after you've created your IAM user.

### Create IAM Groups

Now that we have a policy that enforces the use of MFA and a role that can be assumed.
Let's create a group that users can belong to (better to manage permissions via groups than by users).

Let's go and create one more policy, we will establish a "trust relationship" between our group and our role, so that the members of the former can assume the latter.
1. Go to the "IAM Services" dashboard.
1. On the left-hand sidebar, click "Policies".
1. Click "Create Policy", button may be on top-right.
1. Click the "JSON" tab and copy paste the IAM policy document, and add the following (this is where we finally enforce MFA).
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": [
                "arn:aws:iam::123456789012:role/{Administrator,PowerUser}"
            ],
            "Condition": {
                "Bool": {
                    "aws:MultiFactorAuthPresent": true
                }
            }
        }
    ]
}
``` 
And you know the rest of the steps needed to create a policy.

Now, let's go and create the group.
1. Go to the "IAM Services" dashboard.
1. On the left-hand side, click on "User groups".
1. Click on "Create group".
1. Name your group and assign the policy you created just before this (the one that establishes the trust relationship) AND the policy you created earlier to enforce MFA.
1. Click "Create group".


### Creating IAM Users

We can now finally create IAM users and have them all ready to use.
To create an IAM user do the following

1. Go to the "IAM Services" dashboard.
2. On the left-hand sidebar, click on "Users".
3. Then on the right, you should see a button for "Add Users".
4. On the first screen, you will be asked to give your user(s) a name, do so.
5. On the first screen, you will also see the "Select AWS access type" section. Chose both options, we already created the IAM policies that will enforce MFA on the AWS console and whenever we use the AWS APIs.
  1. Note that we are granting IAM users both programmatic and console access so that the IAM user can sign in and create an MFA device - even if we use the CLI or an AWS SDk, we will be required to use MFA!
6. Ignore the second screen, for now, the MFA enforcement policy we created will prevent the user from changing its initial password. Then click "Next: Tags".
7. Ignore the third screen as well, Click "Next: Review".
8. If everything looks good, click "Create User".
9. If you created an IAM user with console access, the last screen will have a banner showing you the link the IAM user can use to sign in, the password will also be shown at the bottom.

**Note:** Once you've created this IAM user, sign in as it and change its password. Once you've done that, sing out and sign back in as your root user. Then add your newly created IAM user into the IAM group you created. You are essentially onboarding someone right now, you make sure their account works (verify identity), and then you grant them the access they need.

Now, after you were able to sign in as your IAM user, you changed its generated password, and then you added it to the IAM group you created, go and set up its MFA.
1. Sign in as your IAM user.
1. CLick on the menu on the top-right (the one showing your IAM user name and your account ID).
1. Click on "Security credentials".
1. Look for the button that says "Assign MFA device".
1. Then follow the steps the pop-up provides. It will walk you through configuring an MFA device.
1. Once you've set up your MFA device, sign out and sign back in (rememeber that your access is limited if you are not using MFA).

Now, when you sign into the console with your IAM user, you will be able to manage its credentials.
However, if you want to actually use any AWS services, then you will need to assume the role we created earlier.
The rest of that post will cover how to do it programatically, but if you want to assume your role in the console, remember that "Link to switch roles in console" we got when we created the IAM role?
Well now it is the time to try it out.
Though that link is deterministic and you can fill it out
```
https://signin.aws.amazon.com/switchrole?account=<account_id_number>&roleName=<role_name>&displayName=<text_to_display>
```
See
[Switching to a role (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-console.html).


---

## Tools

### AWS-Vault
The one tool I'd recommend, when working with AWS is:
[github.com/99designs/aws-vault](https://github.com/99designs/aws-vault).
Make sure to read
[Securing AWS Credentials on Engineer’s Machines ](https://99designs.com.au/blog/engineering/aws-vault/).

Among many useful features, `aws-vault` will NOT keep your aws access key ID and secret access key stored in plain text.
For example, if you are using a Mac, `aws-vault` will create a custom keychain in `/users/${USER}/Library/Keychains`, it'll be called something like
`aws-vault.keychain-db` (which you can add to the keychain app by clicking File > Add keychain...).
Plus it will also allow you to readily assume the role you configured for access.

As an example,
If your `~/.aws/config` file looks a tad like this
```
[profile <username>]
region = us-west-2
output = json
mfa_serial = arn:aws:iam::123456789012:mfa/<username>

[profile <role-name>]
source_profile = <username>
role_arn = arn:aws:iam::123456789012:role/<role-to-assume>
source_identity = value
session_tags = key1=value1,key2=value2
```

Then you'll be able to store your AWS access key ID and access secret key by running
```
aws-vault add <username>
```

Then you can rotate these (the access key ID and access secret key) by running
```
aws-vault rotate <username>
```

If you want to assume the `<role-name>` role so that you can actually do some work, then as easy as
```
aws-vault exec <role-name>
```

And the temporary credentials will be cached for you
```
aws-vault list
```

---

## EC2s

Before we go and click or run any commands, familiarize yourself with these pages
* [Amazon EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
* [Amazon EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
* [Amazon EC2 Spot Instances Pricing](https://aws.amazon.com/ec2/spot/pricing/)

A general tip: t3.xlarge and t3.2xlarge as spot instances are very good and relatively easy to get (you don't always get a spot instance, you do always get an on-demand one).
If you want arm64 based machines, t3a and t4g are very good.
May also be good to read
[Standard mode for burstable performance instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-standard-mode.html).

We won't go into much detail on how to connect to ec2s, because there are many ways possible and many configurations but here are some tips and useful links
1. Do NOT use a password to SSH into a machine, use SSH key pairs.
1. Do NOT allow SSH from all of the internet, restrict it to your IP.
1. Try to not allow the root user to SSH into your machine.

Now for links (EC2 Instance Connect, documentation for Windows and Linux key pairs, AWS' SSH docs)
* [What are best practices for accessing my EC2 Linux instance securely using SSH while avoiding unauthorized access?](https://aws.amazon.com/premiumsupport/knowledge-center/ec2-ssh-best-practices/)
* [Use EC2 Instance Connect to provide secure SSH access to EC2 instances with private IP addresses](https://aws.amazon.com/blogs/security/use-ec2-instance-connect-to-provide-secure-ssh-access-to-ec2-instances-with-private-ip-addresses/)
* [Connect to your Linux instance using EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Connect-using-EC2-Instance-Connect.html)
* [Connect to your Linux instance using SSH](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html)
* [Amazon EC2 key pairs and Linux instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
* [Amazon EC2 key pairs and Windows instances](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-key-pairs.html)

## Using an EC2 via SSH

To SSH into an EC2, you will first need to create a "key pair".
A key pair will integrate with an EC2 instance so that your public key ends up in the EC2 and the private one ends up in your computer.
However, it is best to create a set of SSH keys with a password (this will protect your private key).
This also means that you will need to "import" (your public key) into a key pari.
To do so, generate a key pair, set a good password, and import it by doing the following
1. EC2 dashbaord
1. key pairs
1. Actions > Import key pair

Once you have a key pair, do the following to spin up an EC2
1. EC2 dashboard
1. Launch Instance
1. Name it
1. Chose AMI
1. Chose instance type
1. Chose the key pair you previously created
1. Select Create security group
1. Select Allow SSH from and chose My IP
1. On storage, set Encrypted to Yes and use the default KMS key (you may have to click on Advanced, for these options to show up)
1. If you want to keep the data you will use in your EC2, set Delete on termination to No
1. (Optional) Advanced details Request Spot Instance

If you did request a spot instance and you want to terminate/stop it, you will have to click on the "Spot Requests" option
in the EC2 dashboard and cancel the request for your EC2 before you can terminate it.

## Restoring your Data

If you terminated your instance but want to get the data you had in there then you have a couple options:
1. Create a new EC2, stop it, detach its root volume and attach your old volume.
1. Mount your old volume.

### Replace a Root Volume

To replace the root volume of your machine (which is not straightforward to do if you requested it as a spot instance)
you need to stop the instance, detach the root volume, then you can attach an old one.

### Mount an EBS Volume

The instructions for this are more elaborate but very well explained in
[Make an Amazon EBS volume available for use on Linux](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html).
Just a couple of useful notes:

If you try to mount your volume and you get a message like the following
```
mount: /data: wrong fs type, bad option, bad superblock on /dev/xvdf, missing codepage or helper program, or other error.
```

It is possible that the error may be due to the fact that your old EBS was a root volume and was already partitioned, as explained by this comment:
> Looks like you have partitioned that block device. In this case, you need to mount `/dev/xvdf1`, not just `/dev/xvdf`.
Source [Cannot mount an existing EBS on AWS](https://serverfault.com/questions/632905/cannot-mount-an-existing-ebs-on-aws).

You may also noticed the above when you run `lsblk` as you will see the disk with multiple partitions
```
$ lsblk
NAME     MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
...
xvda     202:0    0    8G  0 disk
├─xvda1  202:1    0  7.9G  0 part /
├─xvda14 202:14   0    4M  0 part
└─xvda15 202:15   0  106M  0 part /boot/efi
xvdf     202:80   0    8G  0 disk
├─xvdf1  202:81   0  7.9G  0 part
├─xvdf14 202:94   0    4M  0 part
└─xvdf15 202:95   0  106M  0 part
```

Also, if you want to unmount your volume, you can do so by executing the following command
```
sudo umount /data
```
