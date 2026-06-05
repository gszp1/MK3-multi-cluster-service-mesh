resource "tls_private_key" "core_pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "core-kp" {
  key_name   = "core-key"
  public_key = tls_private_key.core_pk.public_key_openssh
}

resource "local_file" "core_key" {
  content         = tls_private_key.core_pk.private_key_pem
  filename        = "${path.module}/outputs/core-key.pem"
  file_permission = "0400"
}