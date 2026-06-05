output "core_public_ip" {
  description = "Public IP address of the core EC2 instance"
  value       = aws_instance.core.public_ip
}

output "core_public_dns" {
  description = "Public DNS hostname of the core EC2 instance"
  value       = aws_instance.core.public_dns
}

resource "local_file" "config" {
  content = jsonencode({
    core = {
      public_ip  = aws_instance.core.public_ip
      public_dns = aws_instance.core.public_dns
    }
  })
  filename        = "${path.module}/outputs/config.json"
  file_permission = "0644"
}
