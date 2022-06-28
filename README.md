# ivy ami-bakery

Bakes tasty AMIs, just for you!

`Packer + Ansible = <3`

## How to create an Ivy environment

Go
[here](https://github.com/nxtlytics/ivy-documentation/blob/master/howto/Processes/Creating_new_AWS_GovCloud_accounts.md#setup-ivy-environment-works-on-commercial-and-govcloud-aws)

## Structure

- `providers` - cloud providers and their image sets
  - `images` - sets of Ansible roles that can be ran against an instance to
    create a machine image for the given provider
    An `image` will translate into an `ami` or the provider-specific version of
    a machine image.

- `roles` - ansible roles applied against a given image
  Plain Jane Ansible roles.

## How do I use this?

This requires:

- packer
- docker (on the host)
- IAM role

<!-- markdownlint-disable MD013 -->

```shell
Bake AMI from Ansible roles using Packer

 Usage: build.sh -p PROVIDER
                 -i IMAGE
                 -r REGION [-r OTHER_REGION]
                 -m MULTI-ACCOUNT_PROFILE
                 -v 'var1_name=value1' [-v 'var2_name=value2']
                 -d
                 --disable-azure-compatibility

 Options:
   --disable-azure-compatibility  disable azure compatibility
   -d,--debug                     enable debug mode
   -i,--image                     image to provision
   -m,--multiaccountprofile       awscli profile that can assume role to list all accounts in this org
   -p,--provider                  provider to use (amazon|google|nocloud|...)
   -r,--region                    regions to copy this image to (can be used multiple times)
   -v,--packer-var                variables and their values to pass to packer, key value pairs (can be used multiple times)
```

<!-- markdownlint-enable MD013 -->

Examples:

```shell
$ AWS_PROFILE=your-profile ./build.sh \
    -p amazon -i ivy-base \
    -v 'datadog_api_key=your-datadog-api-key'
$ AWS_PROFILE=your-profile ./build.sh \
    -p amazon -i ivy-mesos
```

## Common errors

<!-- markdownlint-disable MD013 -->

### `The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances`

<!-- markdownlint-enable MD013 -->

As an aws administrator run the command below:

```shell
aws --profile=your-aws-profile iam create-service-linked-role \
  --aws-service-name spot.amazonaws.com
```

Source: [here](https://stackoverflow.com/questions/64136679/error-the-provided-credentials-do-not-have-permission-to-create-the-service-lin)
