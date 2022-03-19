data "aws_eks_cluster" "cluster" {
  name = var.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_id
}

data "aws_availability_zones" "available" {
}

provider "kubernetes" {
  host                   = element(concat(data.aws_eks_cluster.cluster.*.endpoint, [""]), 0)
  cluster_ca_certificate = base64decode(element(concat(data.aws_eks_cluster.cluster.*.certificate_authority.0.data, [""]), 0))
  token                  = element(concat(data.aws_eks_cluster_auth.cluster.*.token, [""]), 0)
}

locals {
  kubeconfig = yamlencode(
    {
      apiVersion      = "v1"
      kind            = "Config"
      current-context = "terraform"
      clusters = [{
        name = var.cluster_id
        cluster = {
          certificate-authority-data = var.cluster_certificate_authority_data
          server                     = var.cluster_endpoint
        }
      }]
      contexts = [{
        name = "terraform"
        context = {
          cluster = var.cluster_id
          user    = "terraform"
        }
      }]
      users = [{
        name = "terraform"
        user = {
          token = data.aws_eks_cluster_auth.cluster.token
        }
      }]
    }
  )
  current_auth_configmap = yamldecode(var.aws_auth_configmap_yaml)

  merged_permissions = {
    mapRoles = yamlencode(
      distinct(concat(
        yamldecode(local.current_auth_configmap.data.mapRoles), var.map_roles, )
    ))
    mapUsers    = yamlencode(var.map_users)
    mapAccounts = yamlencode(var.map_accounts)
  }


}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
    labels = merge(
      {
        "app.kubernetes.io/managed-by" = "Terraform"
        # / are replaced by . because label validator fails in this lib
        # https://github.com/kubernetes/apimachinery/blob/1bdd76d09076d4dc0362456e59c8f551f5f24a72/pkg/util/validation/validation.go#L166
        "terraform.io/module" = "terraform-aws-modules.eks.aws"
      },
      var.aws_auth_additional_labels
    )
  }

  data = {
    mapRoles = yamlencode(
      distinct(concat(
        yamldecode(local.current_auth_configmap.data.mapRoles), var.map_roles, )
    ))
    mapUsers    = yamlencode(var.map_users)
    mapAccounts = yamlencode(var.map_accounts)
  }

}
