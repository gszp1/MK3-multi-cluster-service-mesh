resource "aws_security_group" "core-sg" {
  name        = "core-sg"
  description = "Security group for core node"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "K8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "core-sg"
    Project = "multi-cluster-service-mesh"
  }
}

resource "aws_instance" "core" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.large"
  vpc_security_group_ids = [aws_security_group.core-sg.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name
  key_name               = aws_key_pair.core-kp.key_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name    = "core"
    Project = "multi-cluster-service-mesh"
  }
}