provider "aws" {
  region = "ap-south-1"
  profile = "kritik"  //This is the Mumbai Region
}

// Generating a private key
resource "tls_private_key" "tls_key" {
  algorithm = "RSA"
  rsa_bits = 2048
}

// Creating a private key file using the above content generation in the current location
resource "local_file" "key_file" {
  content = tls_private_key.tls_key.private_key_pem
  filename = "ha-cluster.pem"
  file_permission = "0400"

  depends_on = [ tls_private_key.tls_key ]
}

// Creating the AWS Key pair using the private key
resource "aws_key_pair" "ha_key" {
  key_name = "ha-key"
  public_key = tls_private_key.tls_key.public_key_openssh

  depends_on = [ tls_private_key.tls_key ]
}

// Create an VPC
resource "aws_vpc" "hacluster_vpc" {
  cidr_block = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
    "Name" = "ha"
  }
}

// Create a subnets inside my vpc for each availability zone
resource "aws_subnet" "hapublic-1" {
  depends_on = [ aws_vpc.hacluster_vpc ]

  vpc_id = aws_vpc.hacluster_vpc.id
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a" // In which zone does this subnet would be created
  map_public_ip_on_launch = true // Assign public ip to the instances launched into this subnet

  tags = {
    "Name" = "public_Subnet-1"
  }
}

resource "aws_subnet" "hapublic-2" {
  depends_on = [ aws_vpc.hacluster_vpc ]

  vpc_id = aws_vpc.hacluster_vpc.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1b" // In which zone does this subnet would be created
  map_public_ip_on_launch = true // Assign public ip to the instances launched into this subnet

  tags = {
    "Name" = "public_Subnet-2"
  }
}

# Because t2.micro is not supported in this region
# resource "aws_subnet" "hapublic-3" {
#   depends_on = [ aws_vpc.hacluster_vpc ]

#   vpc_id = aws_vpc.hacluster_vpc.id
#   cidr_block = "192.168.2.0/24"
#   availability_zone = "ap-south-1c" // In which zone does this subnet would be created
#   map_public_ip_on_launch = true // Assign public ip to the instances launched into this subnet

#   tags = {
#     "Name" = "public_Subnet-3"
#   }
# }

// Create a data storing the list of subnets 

data "aws_subnet_ids" "subnet_list" {
  vpc_id = aws_vpc.hacluster_vpc.id
}

# data "aws_subnet" "my_subnets_map" {
#   for_each = data.aws_subnet_ids.subnet_list.ids
#   id       = each.value
# }

// Now create an IGW and attach it to all the subnets so that all gets accessible from public world

resource "aws_internet_gateway" "gw" {
  depends_on = [ aws_vpc.hacluster_vpc, aws_subnet.hapublic-1, aws_subnet.hapublic-2] //, aws_subnet.hapublic-3]  This should only run after the vpc and subnet
  vpc_id = aws_vpc.hacluster_vpc.id
  tags = {
    "Name" = "ha_gw"
  }
}

# Now attach the routing table to the VPC so that user or applications can go outside

# Each route must contain either a gateway_id, an instance_id, a nat_gateway_id, a vpc_peering_connection_id or a network_interface_id. 

# Note that the default route, mapping the VPC’s CIDR block to “local”, is created implicitly and cannot be specified

resource "aws_route_table" "haroute" {
  depends_on = [ aws_internet_gateway.gw ]
  vpc_id = aws_vpc.hacluster_vpc.id
  route {
    # This rule is for going or connecting to the public world
    cidr_block = "0.0.0.0/0" // Represents the destination or where we wants to gp
    gateway_id = aws_internet_gateway.gw.id // This is the target from where we can go to the respective destination
  }

  tags = {
   "Name" = "public-rule"
  }
}

// Now create an association or mapping of the routing table with the subnet because the local routing rule is already or bydefault attached

# resource "aws_route_table_association" "subnetAssociation" {
#   depends_on = [ aws_route_table.haroute ]

#   # Initiating a for loop for all the subnet ids, here using the count is not appropriate

#   #for_each = data.aws_subnet_ids.subnet_list.ids 
#   count = var.instances_per_subnet

#   # Here we can use either of the approach to loop from bottom 2:
#   subnet_id = element(data.aws_subnet_ids.subnet_list.ids[*], count.index)
#   #subnet_id = each.value
#   route_table_id = aws_route_table.haroute.id
# }
resource "aws_route_table_association" "subnetAssociation1" {
  depends_on = [ aws_route_table.haroute ]

  subnet_id = aws_subnet.hapublic-1.id
  route_table_id = aws_route_table.haroute.id
}

resource "aws_route_table_association" "subnetAssociation2" {
  depends_on = [ aws_route_table.haroute ]

  subnet_id = aws_subnet.hapublic-2.id
  route_table_id = aws_route_table.haroute.id
}
# resource "aws_route_table_association" "subnetAssociation3" {
#   depends_on = [ aws_route_table.haroute ]

#   subnet_id = aws_subnet.hapublic-3.id
#   route_table_id = aws_route_table.haroute.id
# }

# Main route table association
resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.hacluster_vpc.id
  route_table_id = aws_route_table.haroute.id
}

// Add the security group rules

resource "aws_security_group" "allowed_rules" {
  depends_on = [ aws_vpc.hacluster_vpc ]

  name = "hacluster"
  description = "Security Group rules for the HAcluster"
  vpc_id = aws_vpc.hacluster_vpc.id
  # Ingrees rules for HA-Cluster
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing ssh connectivity"
    from_port = 22
    protocol = "tcp"
    to_port = 22
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing pcsd connectivity"
    from_port = 2224
    protocol = "tcp"
    to_port = 2224
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing crmd connectivity"
    from_port = 3121
    protocol = "tcp"
    to_port = 3121
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing corosync-qnetd connectivity"
    from_port = 5403
    protocol = "tcp"
    to_port = 5403
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing corosync multicast-udp connectivity"
    from_port = 5404
    protocol = "udp"
    to_port = 5404
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing corosync connectivity"
    from_port = 5405
    protocol = "udp"
    to_port = 5405
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing CLVM connectivity"
    from_port = 21064
    protocol = "tcp"
    to_port = 21064
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing booth-ticket manager connectivity"
    from_port = 9929
    protocol = "tcp"
    to_port = 9929
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing booth-ticket manager connectivity"
    from_port = 9929
    protocol = "udp"
    to_port = 9929
  }
  egress {
    cidr_blocks = [ "0.0.0.0/0" ]
    from_port = 0
    protocol = -1
    to_port = 0
  }

  tags = {
    "Name" = "HA-firewall-rules"
  }
}

# Now launch the 4 instances in the 2 different public subnets

resource "aws_instance" "ha-nodes-1" {
  #for_each = data.aws_subnet_ids.subnet_list.ids 
  count = var.instances_per_subnet
  ami = var.aws_ami_id
  instance_type = var.instance_type
  key_name = "ha-key"
  subnet_id = aws_subnet.hapublic-1.id
  #subnet_id = each.value
  vpc_security_group_ids = [ aws_security_group.allowed_rules.id ]
}

resource "aws_instance" "ha-nodes-2" {
  #for_each = data.aws_subnet_ids.subnet_list.ids 
  count = var.instances_per_subnet
  ami = var.aws_ami_id
  instance_type = var.instance_type
  key_name = "ha-key"
  subnet_id = aws_subnet.hapublic-2.id
  #subnet_id = each.value
  vpc_security_group_ids = [ aws_security_group.allowed_rules.id ]
}

# Create an EBS Volume
resource "aws_ebs_volume" "terra-vol-1" {
  depends_on = [ aws_instance.ha-nodes-1 ]
  availability_zone = aws_instance.ha-nodes-1[0].availability_zone
  size              = var.ebs_size
  multi_attach_enabled = true
  
  tags = {
    Name = "ebs-vol"
  }
}

# Now attach this volume to the ec2 instances
resource "aws_volume_attachment" "ebs_att-1" {
  count =  var.instances_per_subnet
  device_name  = var.ebs_device_name
  volume_id    = aws_ebs_volume.terra-vol-1.id
  instance_id  = element(aws_instance.ha-nodes-1.*.id, count.index)
  force_detach = true
depends_on = [
  aws_instance.ha-nodes-1,
  aws_ebs_volume.terra-vol-1
  ]
}

# Create an EBS Volume
resource "aws_ebs_volume" "terra-vol-2" {
  depends_on = [ aws_instance.ha-nodes-2 ]
  availability_zone = aws_instance.ha-nodes-2[0].availability_zone
  size              = var.ebs_size
  # multi_attach_enabled = true
  
  tags = {
    Name = "ebs-vol-2"
  }
}

# Now attach this volume to the ec2 instances
resource "aws_volume_attachment" "ebs_att-2" {
  count =  var.instances_per_subnet
  device_name  = var.ebs_device_name
  volume_id    = aws_ebs_volume.terra-vol-2.id
  instance_id  = element(aws_instance.ha-nodes-2.*.id, count.index)
  force_detach = true
depends_on = [
  aws_instance.ha-nodes-2,
  aws_ebs_volume.terra-vol-2
  ]
}

# Prepare the ha cluster nodes to be served through ansible

resource "null_resource" "setupRemoteNodes-1" {
  count = var.instances_per_subnet

  depends_on = [ aws_instance.ha-nodes-1 ]
    # Ansible requires that the remote system has python already installed in it
  provisioner "remote-exec" {
  inline = ["sudo yum install python3 -y"]
  }
  connection {
    type = "ssh"
    host = element(aws_instance.ha-nodes-1.*.public_ip, count.index)
    private_key = file(var.private_key)
    user = var.ansible_user
  }

}

resource "null_resource" "setupRemoteNodes-2" {
  count = var.instances_per_subnet

  depends_on = [ aws_instance.ha-nodes-2 ]
    # Ansible requires that the remote system has python already installed in it
  provisioner "remote-exec" {
  inline = ["sudo yum install python3 -y"]
  }
  connection {
    type = "ssh"
    host = element(aws_instance.ha-nodes-2.*.public_ip, count.index)
    private_key = file(var.private_key)
    user = var.ansible_user
  }

}


# # Now we nedd to setup environment for Ansible to run, for this we make use of local-exec & remote-exec modules of terraform
resource "null_resource" "setupAnsible" {
  depends_on = [ aws_instance.ha-nodes-2 ]
  provisioner "local-exec" {
    command = <<EOT
      sleep 20;
      >./playbooks/inventory.ini;
	echo "[hanodes_public]" | tee -a ../playbooks/inventory.ini;
	echo "${aws_instance.ha-nodes-1[0].public_dns} private_ip=${aws_instance.ha-nodes-1[0].private_dns} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a ./playbooks/inventory.ini;
	echo "${aws_instance.ha-nodes-1[1].public_dns} private_ip=${aws_instance.ha-nodes-1[1].private_dns} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a ./playbooks/inventory.ini;
  echo "${aws_instance.ha-nodes-2[0].public_dns} private_ip=${aws_instance.ha-nodes-2[0].private_dns} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a ./playbooks/inventory.ini;
  echo "${aws_instance.ha-nodes-2[1].public_dns} private_ip=${aws_instance.ha-nodes-2[1].private_dns} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a ./playbooks/inventory.ini;
      	export ANSIBLE_HOST_KEY_CHECKING=False;
         cd ./playbooks;
        ansible-playbook -i inventory.ini ha-cluster.yaml --vault-password-file .passwd;
    	EOT
  }

}


