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
  filename = "storage.pem"
  file_permission = "0400"

  depends_on = [ tls_private_key.tls_key ]
}

// Creating the AWS Key pair using the private key
resource "aws_key_pair" "ha_key" {
  key_name = "storage-key"
  public_key = tls_private_key.tls_key.public_key_openssh

  depends_on = [ tls_private_key.tls_key ]
}

// Create an VPC
resource "aws_vpc" "storage_vpc" {
  cidr_block = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
    "Name" = "ha"
  }
}

// Create a subnets inside my vpc for each availability zone
resource "aws_subnet" "storage_subnet" {
  depends_on = [ aws_vpc.storage_vpc ]

  vpc_id = aws_vpc.storage_vpc.id
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a" // In which zone does this subnet would be created
  map_public_ip_on_launch = true // Assign public ip to the instances launched into this subnet

  tags = {
    "Name" = "public_Subnet-1"
  }
}


resource "aws_security_group" "storage_rules" {
  depends_on = [ aws_vpc.storage_vpc ]

  name = "block-storage"
  description = "Security Group rules for the Block Storage"
  vpc_id = aws_vpc.storage_vpc.id
  # Ingrees rules for Storage
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing ssh connectivity"
    from_port = 22
    protocol = "tcp"
    to_port = 22
  }
  ingress {
    cidr_blocks = [ "0.0.0.0/0" ] # Here it mean from where the client can enter i.e client origin
    description = "Allowing iscsi tcp connectivity"
    from_port = 3260
    protocol = "tcp"
    to_port = 3260
  }
  egress {
    cidr_blocks = [ "0.0.0.0/0" ]
    from_port = 0
    protocol = -1
    to_port = 0
  }

  tags = {
    "Name" = "Storage-firewall-rule"
  }
}

# Now launch the storage server node
resource "aws_instance" "storage_node" {
  ami = "ami-08f63db601b82ff5f"
  instance_type = var.instance_type
  key_name = "ha-key"
  subnet_id = aws_subnet.hapublic-2.id
  vpc_security_group_ids = [ aws_security_group.storage_rules.id ]
}

# Create an EBS Volume
resource "aws_ebs_volume" "terra-vol" {
  availability_zone = aws_instance.storage_node.availability_zone
  size              = 8
  multi_attach_enabled = true
  
  tags = {
    Name = "ebs-vol-2"
  }
}

# Now attach this volume to the ec2 instances
resource "aws_volume_attachment" "ebs_att-2" {
  device_name  = "/dev/sdh"
  volume_id    = aws_ebs_volume.terra-vol.id
  instance_id  = aws_instance.storage_node.id
  force_detach = true
depends_on = [
  aws_instance.storage_node,
  aws_ebs_volume.terra-vol
  ]
}

# Prepare the storage node to be served through ansible

resource "null_resource" "setupRemoteStorage" {

  depends_on = [ aws_instance.storage_node ]
    # Ansible requires that the remote system has python already installed in it
  provisioner "remote-exec" {
  inline = ["sudo yum install python3 python-dbus -y "]
  }
  connection {
    type = "ssh"
    host = aws_instance.storage_node.public_ip
    private_key = file(var.private_key)
    user = var.ansible_user
  }

}

# Now we nedd to setup environment for Ansible to run, for this we make use of local-exec & remote-exec modules of terraform
resource "null_resource" "setupAnsible" {
  # depends_on = [ aws_instance ]
  provisioner "local-exec" {
    command = <<EOT
      sleep 20;
      >./playbooks/inventory.ini;
	export ANSIBLE_HOST_KEY_CHECKING=False;
    echo "[iscsi]" | tee -a ../playbooks/inventory.ini;
    echo "${aws_instance.storage_node.public_dns} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a ../playbooks/inventory.ini;
    ansible-playbook -i inventory.ini iscsi.yaml;
    	EOT
  }

}