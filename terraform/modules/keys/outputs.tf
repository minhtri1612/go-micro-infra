output "key_name" {
  value = aws_key_pair.this.key_name
}

output "private_key_filename" {
  value = local_file.private_key.filename
}
