# Setup a trust between parent and children account to allow the child to list accounts

**NOTE**: Run this only if you follow a multi account organization.

## AMIBuilder ec2 instance dependencies

<!-- markdownlint-disable MD013 -->

- [packer](https://packer.io/downloads.html)
- [docker](https://docs.docker.com/install/)
  - if in amazon linux run
    `amazon-linux-extras enable docker && yum clean metadata && yum install docker && systemctl start docker`
- [~/.aws/config](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
  , see below:

<!-- markdownlint-enable MD013 -->

### Commercial AWS

```shell
$ cat ~/.aws/config
[profile orgs]
role_arn=arn:aws:iam::<Parent Account ID>:role/ORGSReadOnlyTrust
credential_source=Ec2InstanceMetadata
```

### GovCloud AWS

```shell
$ cat ~/.aws/config
[profile default]
region = us-gov-west-1

[profile orgs]
role_arn=arn:aws-us-gov:iam::<Parent Account ID>:role/ORGSReadOnlyTrust
credential_source=Ec2InstanceMetadata
region = us-gov-west-1
```

### AWS China

```shell
$ cat ~/.aws/config
[profile default]
region = cn-north-1

[profile orgs]
role_arn=arn:aws-cn:iam::<Parent Account ID>:role/ORGSReadOnlyTrust
credential_source=Ec2InstanceMetadata
region = cn-north-1
```
