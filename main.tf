# Below are resources needed for enabling the consul auto-join function. 
# EC2 instaces need to have iam_instance_profile with the below policy and 
# set of rules so each EC2 can read the metadata in order to find the private_ips based on a specific tag key/value.
data "terraform_remote_state" "nw" {
  backend = "remote"

  config = {
    organization = "webpage-counter"
    workspaces = {
      name = "ops-aws-network"
    }
    token = var.token
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "consul" {
  name_prefix        = "consul_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "consul" {
  statement {
    sid       = "AllowSelfAssembly"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "ec2:DescribeVpcs",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
  }
}

resource "aws_iam_role_policy" "consul" {
  name_prefix = "consul_role"
  role        = aws_iam_role.consul.id
  policy      = data.aws_iam_policy_document.consul.json
}

resource "aws_iam_instance_profile" "consul" {
  name_prefix = "consul_role"
  role        = aws_iam_role.consul.name
}

# Data source that is needed in order to dinamicly publish values of variables into the script that is creating Consul configuration files and starting it.

data "template_file" "var" {
  template = file("${path.module}/scripts/start_consul.tpl")

  vars = {
    DOMAIN       = var.domain
    DCNAME       = var.dcname
    LOG_LEVEL    = "debug"
    SERVER_COUNT = var.server_count
    var2         = "$(hostname)"
    IP           = "$(hostname -I | cut -d \" \" -f1)"
    JOIN_WAN     = var.join_wan
  }
}

# Below are the 3 Consul servers and 1 consul client.
resource "aws_instance" "consul_servers" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.nw.outputs.public_subnets[0]
  vpc_security_group_ids      = ["${data.terraform_remote_state.nw.outputs.pubic_sec_group}"]
  iam_instance_profile        = aws_iam_instance_profile.consul.id
  private_ip                  = "${var.IP["server"]}${count.index + 1}"
  associate_public_ip_address = false  
  count                       = var.server_count
  user_data                   = data.template_file.var.rendered
  depends_on                  = [data.terraform_remote_state.nw]

  tags = {
    Name     = "consul-server${count.index + 1}"
    consul   = var.dcname
    join_wan = var.join_wan
  }

}

# Outputs the instances public ips.


output "ami" {
  value = var.ami
}

output "instance_type" {
  value = aws_instance.consul_servers[0].instance_type
}

output "security_group_id" {
  value = aws_instance.consul_servers[0].vpc_security_group_ids
}

output "dcname" {
  value = var.dcname
}

output "IP_client" {
  value = var.IP["client"]
}

output "subnet_id" {
  value = aws_instance.consul_servers[0].subnet_id
}

output "data_rendered" {
  value      = data.template_file.var.rendered
  depends_on = [data.template_file.var]
}

output "iam_instance_profile" {
  value = aws_iam_instance_profile.consul.id
}


