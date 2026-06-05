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

  provisioner "remote-exec" {
    inline = [
      "sudo sysctl -w fs.inotify.max_user_watches=524288",
      "sudo sysctl -w fs.inotify.max_user_instances=512",
      "echo 'fs.inotify.max_user_watches=524288' | sudo tee -a /etc/sysctl.conf",
      "echo 'fs.inotify.max_user_instances=512'  | sudo tee -a /etc/sysctl.conf",
      "sudo curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64",
      "sudo chmod +x /usr/local/bin/kind",
      "curl -LO \"https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "rm kubectl",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.core_pk.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ec2-user/cluster"]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.core_pk.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "file" {
    source      = "${path.module}/../cluster/"
    destination = "/home/ec2-user/cluster"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.core_pk.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "kind create cluster --name primary  --config /home/ec2-user/cluster/primary.yml",
      "kind create cluster --name remote-1 --config /home/ec2-user/cluster/remote-1.yml",
      "kind create cluster --name remote-2 --config /home/ec2-user/cluster/remote-2.yml",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.core_pk.private_key_pem
      host        = self.public_ip
    }
  }
}