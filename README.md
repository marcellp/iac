# iac

Our infrastructure as code.

### Base infrastructure
Base infrastructure means infrastructure required for Cellenics to be deployed.
This broadly corresponds to the kubernetes cluster and closely related infrastructure. This
infrastructure is deployed *manually* by launching the action *Deploy Cellenics infrastructure*
from the [actions](https://github.com/hms-dbmi-cellenics/iac/actions?query=workflow%3A%22Deploy+Cellenics+infrastructure+on+AWS%22).
The configuration for these infraustructure components are under `infra/`.

#### AWS Permssions for Github workflows
AWS permissions required by Github workflows are carried out through [OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). When setting up a new deployment, you have to **manually** create a new CloudFormation stack to setup the required IAM permissions for IAC as defined in `infra/cf-github-oidc`.  This should only be done once per AWS account.

#### Required secrets to deploy infrastructure
Some secrets are required to deploy infrastructure into AWS and configure the infrastructure and deployment:

- AWS_ACCOUNT_ID

  The AWS account ID to deploy to.

- API_TOKEN_GITHUB

  API token from the Github account that will be used by Flux to access and manage this repository.

- DOMAIN_NAME

  The domain name that Cellenics will be deployed under (e.g. cellenics.app.net)

- DOMAIN_NAME_STAGING (optional, used only if the deployment is not on a production environment)

  The domain that the staging instance of Cellenics will be deployed under (e.g. cellenics-staging.app.net)

- PRIMARY_DOMAIN_NAME

  The primary domain name where Cellenics will be deployed under (e.g. app.net). This is the name of the domain
  in the hosted zone.

- RDS_TUNNEL_PORT

  Port number for RDS migration

- ACM_CERTIFICATE_ARN

 The AWS ACM ARN for the SSL certificate for the Cellenics domain name.

- DATADOG_API_KEY

  The [Datadog API key](https://docs.datadoghq.com/account_management/api-app-keys/#api-keys) of the Datadog account.

- DATADOG_APP_KEY

  The [Datadog application](https://docs.datadoghq.com/account_management/api-app-keys/#application-keys) key created for the Datadog account for AWS Batch monitoring. This can be created in the Organization Settings submenu inside the Datadog account.


#### Changing base infrastructure
The github workflow that triggers an update to the base infrastructure with the files in `infra/` is [deploy-infra.yaml](https://github.com/hms-dbmi-cellenics/iac/blob/master/.github/workflows/deploy-infra.yaml). At the moment, this workflow has to be manually triggered for the update to happen. To trigger an update, you have to:
1. Go to the *Deploy Cellenics infrastructure*
[actions](https://github.com/hms-dbmi-cellenics/iac/actions?query=workflow%3A%22Deploy+Cellenics+infrastructure+on+AWS%22). Select *Deploy Cellenics infrastructure* workflow from the list of workflows.
2. Click on `Run workflow` dropdown on the right side of the top workflow result. With this dropdown, you will configure the inputs with which the workflow will be run.
3. `Use worklow from` defines which changes the build will be run wuth. Make sure it is set to `master` to avoid situations when infrastructure changes from other branch are deployed and we have unknown state.
4. `Select actions to perform` defines what kind of changes you want to apply to the infrastructure. There are 2 options available to select from:

    - `deploy and configure`: If you've made changes that require re-creation of the cluster. For example: changing the EC2 node type.
    - `configure`: The default option. If you've made changes that only require update of the configuratio of the existing cluster. Most of the time, you will need to use option `configure`.

5. After you've made your selections, click `run workflow`. This will update or recreate and update the cluster in the AWS region specified using the state of the iac repo in the branch selected in `use workflow from`.

### The Kubernetes Cluster

The cluster is deployed using [eksctl](https://eksctl.io/introduction/) by the CI pipeline. The
corresponding *ClusterConfig* is available under `infra/cluster.yaml`.

Note: per the eksctl documentation, **node groups are immutable**. If you want to change the node group
type, storage size, or any other property, you must delete the old node group from the configuration,
and add a new one with a different name. eksctl will then appropriately drain and set up node groups.

The name of the EKS cluster is always `biomage-$ENVIRONMENT`, where `$ENVIRONMENT` is the cluster environment
(`staging` or `production`). You must add `$ENVIRONMENT` as an environment variable or substitute it accordingly
when you run these commands.

### Accessing the cluster
By default, eksctl only grants cluster admin rights to the user that created the cluster, i.e. the CI
user for the GitHub repo. The file `infra/cluster_admins` contains a list of IAM users for whom admin
rights will be granted. The file `infra/cluster_users` contains a list of IAM users that have only user rights
granted.

#### 1. Make sure you have the correct aws credentials set in your `~/.aws/credentials` file.

To check if your credentials are correct, try running step 2. If step 2 fails with an error saying `error: You must be logged in to the server (Unauthorized)` this means that your current credentials are wrong. In that case, talk to Iva to give you correct ones.

#### 2. Configure kube config to point to the right cluster.
This step guides you through how to configure your kubeconfig file in order to have access to the
cluster locally.
In a new terminal, execute the following commands:

    # remove the old config so that accidental operations on the
    # wrong cluster are prevented.
    $ rm ~/.kube/config

    # grant access to the cluster.
    $ aws eks update-kubeconfig --name biomage-$ENVIRONMENT --region eu-west-1

    # Verify that all worked fine: execute get nodes command
    # If everything is working, you should see something similar to this:
    # NAME                                           STATUS   ROLES    AGE   VERSION
    # ip-192-168-33-132.eu-west-1.compute.internal   Ready    <none>   40h   v1
    # ip-192-168-81-140.eu-west-1.compute.internal   Ready    <none>   40h   v1

    $ kubectl get nodes


#### 3. Access the cluster graphically
This step is optional and lets you use a nice intuitive user interface to interact with Kubernetes.
Simply download and install [lens](https://k8slens.dev/) and then follow the instructions specified there.

### Ingress

Ingress into the cluster is managed by the [AWS Load Balancer Controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller).

After the AWS Load Balancer Controller is installed, the DNS of the hosted domain must be modified to redirect to the
load balancer automatically. This is done automatically as a CloudFormation chart under `infra/cf-route53.yaml`.

Ingress resources need to specify the following in their annotations for them to be managed by the AWS Load Balancer Controller:

    kubernetes.io/ingress.class: alb

This is automatically configured for the charts in this repository.

Read more about this here:
- https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
- https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/guide/ingress/annotations/

**Important**: When the cluster is (re)deployed, there may be a delay in the DNS changes propagating to all hosts on
the internet. If redeploying the infrastructure to another region, **make sure the old deployment still exists**.
There can only be one deployment bound to the domain at any given time. Destroying the old deployment before creating
the new one will result in downtime.

### Charts

The `charts/` folder contains various pre-written charts that are widely useful for deployments.
For example, the `charts/nodejs` chart is for deploying a Node.js server, which is used by
both `ui` and `api` in their HelmRelease configurations.

### AWS resources

AWS resources refer to things not described above that can be managed and configured using
CloudFormation e.g. SQL DB, ElastiCache Redis clusters, S3 buckets, etc. These are
managed *automatically* by a GitHub action, and they are available under `cf/`.

### General resources

Resources under `cf/` are CloudFormation templates that describe a particular deployment.
Changes to `cf/` files are automatically picked up and deployed by the CI pipeline.

**Important:** Make sure each template covers a broadly related group of resources, ideally
consisting of only one type of resource. This ensures applying changes is as easy as possible.

Each CloudFormation template must have an `Environment` parameter that accepts a valid cluster
environment (`staging`, `production`) or `development`. The `development` environment is used
by InfraMock for local mocking of the resource. Templates should use this variable to create
environment-specific resources.

**Important**: Always use the available `AWS::Region` and `AWS::AccountId` variables when
writing CloudFormation templates. This ensures that the resources are portable to various
regions and account IDs.

### IAM Roles for Service Accounts (IRSA) resources

These are a special type of resource, identified by files in the `irsa-*.yaml` format. They
are used by AWS to grant a limited set of permissions to each deployment.

They are regular CloudFormation templates, but they must also accept an `OIDCProvider`
parameter, which is automatically filled in by the pipeline when the changes
are applied. This is used to ensure the role is only granted to the appropriate
service account. See [here](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)
for more details.

The `AssumeRolePolicyDocument` is filled in per the documentation above. Ensure that
the policy follows least privilege in who can access the resources, at least specifying
the correct deployment source and the name of the service account, e.g.:

    system:serviceaccount:worker-*:deployment-runner

The permissions are configured as with any other IAM Role deployment. Make sure these
follow best practice, with each resource appropriately scoped by account ID, region,
environment, etc.
