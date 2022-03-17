data "aws_eks_cluster_auth" "this" {
  name = var.cluster_id
}

locals {
  kubeconfig = yamlencode({
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
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })

  map_roles = var.map_roles

  current_auth_configmap = data.kubernetes_config_map.aws-auth

  updated_auth_configmap_data = {
    data = {
      mapRoles = replace(yamlencode(
        distinct(concat(
          yamldecode(local.current_auth_configmap.data.mapRoles), local.map_roles)
      )), "\"", "")
      mapUsers = yamlencode(local.map_users)
    }
  }

}

resource "null_resource" "apply" {
  triggers = {
    kubeconfig = base64encode(local.kubeconfig)
    cmd_patch  = <<-EOT
      kubectl create configmap aws-auth -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
      kubectl patch configmap/aws-auth --type merge --patch "${chomp(jsonencode(local.updated_auth_configmap_data))}" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
    EOT
  }
  #kubectl patch configmap/aws-auth --patch "${var.aws_auth_configmap_yaml}" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
    command = self.triggers.cmd_patch
  }
}
