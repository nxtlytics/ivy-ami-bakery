# Copy AMI between regions and share with AWS Account IDs under the same org

**NOTE**: Run this only if you follow a multi account organization.

## Dependencies

<!-- markdownlint-disable MD013 -->

- [yq](https://github.com/mikefarah/yq)
- [jq](https://github.com/stedolan/jq)
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

## How to

```shell
$ ./scripts/copy_ami/copy_ami.sh --help
Unknown option --help
Usage:
copy_ami.sh -r, --region-name <AWS region name. Examples: us-east-1, us-west-2. REQUIRED>
            -p, --prefix <AMI name prefix. REQUIRED>

Copy an AMI to another AWS region
```
