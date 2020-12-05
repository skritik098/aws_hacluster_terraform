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

variable "private_key" {
  description = "User required to login to ec2-instance by ansible"
  type = string
  default = "./storage.pem"
}