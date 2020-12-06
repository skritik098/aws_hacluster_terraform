variable "instance_type" {
  description = "Node instance type"
  type = string
  default = "t2.micro"
}

variable "ansible_user" {
  description = "User with which ansible configure"
  type = string
  default = "ec2-user"
}

variable "ami_id" {
  description = "AWS ami id for storage Server"
  type = string
  default = "ami-08f63db601b82ff5f"
}

variable "private_key" {
  description = "User required to login to ec2-instance by ansible"
  type = string
  default = "storage.pem"
}