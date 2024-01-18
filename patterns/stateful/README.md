# Amazon EKS Cluster for Stateful Workloads

## Features

Please note: not all of the features listed below are required for stateful workloads on EKS. We are simply grouping together a set of features that are commonly encountered when managing stateful workloads. Users are encouraged to only enable the features that are required for their workload(s) and use case(s).

### [velero](https://github.com/vmware-tanzu/velero)

(From the project documentation)
`velero` (formerly Heptio Ark) gives you tools to back up and restore your Kubernetes cluster resources and persistent volumes. You can run Velero with a public cloud platform or on-premises. Velero lets you:

- Take backups of your cluster and restore in case of loss.
- Migrate cluster resources to other clusters.
- Replicate your production cluster to development and testing clusters.

### EBS & EFS CSI Drivers

- A second storage class for `gp3` backed volumes has been added and made the default over the EKS default `gp2` storage class (`gp2` storage class remains in the cluster for use, but it is no longer the default storage class)
- A standard implementation of the EFS CSI driver

### EKS Managed Nodegroup w/ Multiple Volumes

An EKS managed nodegroup that utilizes multiple EBS volumes. The primary use case demonstrated in this example is a second volume that is dedicated to the `containerd` runtime to ensure the root volume is not filled up nor has its I/O exhausted to ensure the instance does not reach a degraded state. The `containerd` directories are mapped to this volume. You can read more about this recommendation in our [EKS best practices guide](https://aws.github.io/aws-eks-best-practices/scalability/docs/data-plane/#use-multiple-ebs-volumes-for-containers) and refer to the `containerd` [documentation](https://github.com/containerd/containerd/blob/main/docs/ops.md#base-configuration) for more information. The update for `containerd` to use the second volume is managed through the provided user data.

In addition, the following properties are configured on the nodegroup volumes:

- EBS encryption using a customer managed key (CMK)
- Configuring the volumes to use GP3 storage

### EKS Managed Nodegroup w/ Instance Store Volume(s)

An EKS managed nodegroup that utilizes EC2 instances with ephemeral instance store(s). Instance stores are ideal for temporary storage of information that changes frequently, such as buffers, caches, scratch data, and other temporary content, or for data that is replicated across a fleet of instances. You can read more about instance stores in the [AWS documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html); and be sure to check out the [`Block device mapping instance store caveats`](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html#instance-block-device-mapping) section as well which covers why the example has provided user data for mounting the instance store(s). The size and number of instance stores will vary based on the EC2 instance type and class.

In addition, the following properties are configured on the nodegroup volumes:

- EBS encryption using a customer managed key (CMK)
- Configuring the volumes to use GP3 storage

## Deploy

See [here](https://aws-ia.github.io/terraform-aws-eks-blueprints/getting-started/#prerequisites) for the prerequisites and steps to deploy this pattern.

## Validate

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl` to validate the Velero deployment.

1. Run `update-kubeconfig` command:

    ```bash
    aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
    ```

2. List the storage classes to view that `efs`, `gp2`, and `gp3` classes are present and `gp3` is the default storage class

    ```sh
    kubectl get storageclasses
    ```

    ```text
    NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    efs             efs.csi.aws.com         Delete          Immediate              true                   2m19s
    gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  15m
    gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   2m19s
    ```

3. From an instance launched with instance store(s), check that the instance store has been mounted correctly. To verify, first install the `nvme-cli` tool and then use it to verify. To verify, you can access the instance using SSM Session Manager:

    ```sh
    # Install the nvme-cli tool
    sudo yum install nvme-cli -y

    # Show NVMe volumes attached
    sudo nvme list
    ```

    ```text
    # Notice the model is `EC2 NVMe Instance Storage` for the instance store
    Node             SN                   Model                                    Namespace Usage                      Format           FW Rev
    ---------------- -------------------- ---------------------------------------- --------- -------------------------- ---------------- --------
    /dev/nvme0n1     vol0546d3c3b0af0bf6d Amazon Elastic Block Store               1          25.77  GB /  25.77  GB    512   B +  0 B   1.0
    /dev/nvme1n1     AWS24BBF51AF55097008 Amazon EC2 NVMe Instance Storage         1          75.00  GB /  75.00  GB    512   B +  0 B   0

    # Show disks, their partitions and mounts
    sudo lsblk

    # Output should look like below
    NAME          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    nvme0n1       259:0    0   24G  0 disk
    ├─nvme0n1p1   259:2    0   24G  0 part /
    └─nvme0n1p128 259:3    0    1M  0 part
    nvme1n1       259:1    0 69.9G  0 disk /local1 # <--- this is the instance store
    ```

4. From an instance launched with multiple volume(s), check that the instance store has been mounted correctly. To verify, first install the `nvme-cli` tool and then use it to verify. To verify, you can access the instance using SSM Session Manager:

    ```sh
    # Install the nvme-cli tool
    sudo yum install nvme-cli -y

    # Show NVMe volumes attached
    sudo nvme list
    ```

    ```text
    # /dev/nvme0n1 is the root volume and /dev/nvme1n1 is the second, additional volume
    Node             SN                   Model                                    Namespace Usage                      Format           FW Rev
    ---------------- -------------------- ---------------------------------------- --------- -------------------------- ---------------- --------
    /dev/nvme0n1     vol0cd37dab9e4a5c184 Amazon Elastic Block Store               1          68.72  GB /  68.72  GB    512   B +  0 B   1.0
    /dev/nvme1n1     vol0ad3629c159ee869c Amazon Elastic Block Store               1          25.77  GB /  25.77  GB    512   B +  0 B   1.0
    ```

5. From the same instance used in step 4, check that the containerd directories are using the second `/dev/nvme1n1` volume:

    ```sh
    df /var/lib/containerd/
    ```

    ```text
    # Output should look like below, which shows the directory on the
    # /dev/nvme1n1 volume and NOT on /dev/nvme0n1 (root volume)
    Filesystem     1K-blocks    Used Available Use% Mounted on
    /dev/nvme1n1    24594768 2886716  20433380  13% /var/lib/containerd
    ```

    ```sh
    df /run/containerd/
    ```

    ```text
    # Output should look like below, which shows the directory on the
    # /dev/nvme1n1 volume and NOT on /dev/nvme0n1 (root volume)
    Filesystem     1K-blocks    Used Available Use% Mounted on
    /dev/nvme1n1    24594768 2886716  20433380  13% /run/containerd
    ```

6. Test by listing velero resources provisioned:

    ```bash
    kubectl get all -n velero

    # Output should look similar to below
    NAME                         READY   STATUS    RESTARTS   AGE
    pod/velero-b4d8fd5c7-5smp6   1/1     Running   0          112s

    NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
    service/velero   ClusterIP   172.20.217.203   <none>        8085/TCP   114s

    NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/velero   1/1     1            1           114s

    NAME                               DESIRED   CURRENT   READY   AGE
    replicaset.apps/velero-b4d8fd5c7   1         1         1       114s
    ```

7. Get backup location using velero [CLI](https://velero.io/docs/v1.8/basic-install/#install-the-cli)

    ```bash
    velero backup-location get

    # Output should look similar to below
    NAME      PROVIDER   BUCKET/PREFIX             PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
    default   aws        velero-ssqwm44hvofzb32d   Available   2022-05-22 10:53:26 -0400 EDT   ReadWrite     true
    ```

## Destroy

{%
   include-markdown "../../docs/_partials/destroy.md"
%}
