variable "instances_per_subnet" {
  description = "Number of instance launched in public subnet"
  type = number
  default = 2
}
variable "ebs_size" {
  description = "Number of instance launched in public subnet"
  type = number
  default = 8
}

variable "ebs_device_name" {
  description = "EBS device name"
  type = string
  default = "/dev/sdh"
}

variable "instance_type" {
  description = "Node instance type"
  type = string
  default = "t2.micro"
}

variable "aws_ami_id" {
  description = "Node ami id"
  type = string
  default = "ami-08f63db601b82ff5f"
}

variable "ansible_user" {
  description = "User with which ansible configure"
  type = string
  default = "ec2-user"
}

variable "private_key" {
  description = "User required to login to ec2-instance by ansible"
  type = string
  default = "../terraform/ha-cluster.pem"
}