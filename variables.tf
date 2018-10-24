variable "count" {
  default = 1
}

variable "region" {
  description = "AWS region for hosting our your network"
  default     = "us-east-1"
}

variable "public_key_path" {
  description = "Enter the path to the SSH Public Key to add to AWS."
  default     = "/home/david/Escritorio/cloud/Lab/TerraformAWS/key/AWSKeyTest.pem"
}

variable "key_name" {
  description = "Key name for SSHing into EC2"
  default     = "AWSKeyTest"
}

variable "amis" {
  description = "Base AMI to launch the instances"

  default = {
    us-east-1 = "ami-2757f631"
  }
}
