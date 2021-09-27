#!/bin/bash -x

set -eu -o pipefail

bold=$(tput bold)
norm=$(tput sgr0)

function show_help() {
    cat <<EOT
Copy an Amazon AMI to an Azure storage account and create a shared image

 Usage: $(basename $0) -a AMI_ID -b BUCKET_NAME -r IAM_ROLE -s STORAGE_ACCOUNT -c STORAGE_ACCOUNT_CONTAINER -g RESOURCE_GROUP -i IMAGE_GALLERY_NAME -n IMAGE_NAME -v IMAGE_VERSION

 Options:
   -a    Source AMI ID
   -b    Bucket name to export the image to
   -r    AWS IAM role for the export command to use
   -s    Storage account name
   -c    Storage account container to copy the image from S3 to
   -g    Resource group of the shared image gallery
   -i    Image gallery name of the final destination of the image
   -n    Image name for the AMI
   -v    Image version
EOT
}

while getopts ":a:b:r:s:c:g:i:n:v:" opt; do
    case ${opt} in
        a)
            AMI_ID="${OPTARG}"
            ;;
        b)
            BUCKET_NAME="${OPTARG}"
            ;;
        r)
            IAM_ROLE="${OPTARG}"
            ;;
        s)
            STORAGE_ACCOUNT="${OPTARG}"
            ;;
        c)
            STORAGE_ACCOUNT_CONTAINER="${OPTARG}"
            ;;
        g)
            RESOURCE_GROUP="${OPTARG}"
            ;;
        i)
            IMAGE_GALLERY_NAME="${OPTARG}"
            ;;
        n)
            IMAGE_NAME="${OPTARG}"
            ;;
        v)
            IMAGE_VERSION="${OPTARG}"
            ;;

        \?)
            echo -e "${bold}Invalid option:${norm} ${OPTARG}" 1>&2
            show_help
            exit 1
            ;;
        :)
            echo -e "${bold}Invalid option:${norm} ${OPTARG} requires an argument" 1>&2
            show_help
            exit 1
            ;;
    esac
done

shift $((OPTIND -1))

if [[ -z ${AMI_ID} ]] ||
[[ -z ${BUCKET_NAME} ]] ||
[[ -z ${IAM_ROLE} ]] ||
[[ -z ${STORAGE_ACCOUNT} ]] ||
[[ -z ${STORAGE_ACCOUNT_CONTAINER} ]] ||
[[ -z ${RESOURCE_GROUP} ]] ||
[[ -z ${IMAGE_GALLERY_NAME} ]] ||
[[ -z ${IMAGE_NAME} ]] ||
[[ -z ${IMAGE_VERSION} ]]; then
    echo -e "${bold}ERROR:${norm} Missing required arguments"
    show_help
    exit 1
fi

# export image using aws cli to s3 bucket
export_task_id=$(aws ec2 export-image \
              --image-id "${AMI_ID}" \
              --disk-image-format VHD \
              --role-name "${IAM_ROLE}" \
              --s3-export-location "S3Bucket=${BUCKET_NAME},S3Prefix=exports/" \
              --query "ExportImageTaskId" \
              --output text)

# wait for export image task to finish
while ! aws ec2 describe-export-image-tasks \
--export-image-task-ids "${export_task_id}" \
--query "ExportImageTasks[0].Status" \
--output text | grep -q "completed" ; do
  echo -e "Waiting for AMI export task ${bold}${export_task_id}${norm} to be completed..."
  sleep 10
done

# download image from s3
local_image_path="/tmp/${export_task_id}.vhd"
aws s3 cp "s3://${BUCKET_NAME}/exports/${export_task_id}.vhd" "${local_image_path}"

# upload image to storage account using azure-vhd-utils
storage_account_key=$(az storage account keys list --account-name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --output tsv --query "[0].value")
azure-vhd-utils upload \
  --localvhdpath "${local_image_path}" \
  --stgaccountname "${STORAGE_ACCOUNT}" \
  --stgaccountkey "${storage_account_key}" \
  --containername "${STORAGE_ACCOUNT_CONTAINER}" \
  --blobname "${AMI_ID}.vhd"

# delete local copy of image
rm -f "${local_image_path}"

# delete s3 copy of image

# create image version from image in storage account
vhd_uri="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${STORAGE_ACCOUNT_CONTAINER}/${AMI_ID}.vhd"
az sig image-version create \
  --resource-group "${RESOURCE_GROUP}" \
  --gallery-name "${IMAGE_GALLERY_NAME}" \
  --gallery-image-definition "${IMAGE_NAME}" \
  --gallery-image-version "${IMAGE_VERSION}" \
  --os-vhd-uri "${vhd_uri}" \
  --os-vhd-storage-account "${STORAGE_ACCOUNT}"

# (maybe) delete image from storage account
