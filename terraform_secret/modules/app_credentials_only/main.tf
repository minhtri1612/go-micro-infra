resource "aws_secretsmanager_secret" "app_credentials" {
  name                    = "${var.project_name}/${var.environment}/app-credentials${var.app_credentials_name_suffix}"
  description             = "Application credentials for ${var.environment}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_credentials" {
  secret_id = aws_secretsmanager_secret.app_credentials.id
  secret_string = jsonencode({
    DB_USER              = var.db_user
    DB_PASSWORD          = var.db_password
    POSTGRES_USER        = var.db_user
    POSTGRES_PASSWORD    = var.db_password
    PRODUCT_DB_NAME      = "products_db"
    ORDER_DB_NAME        = "orders_db"
    INVENTORY_DB_NAME    = "inventory_db"
    NOTIFICATION_DB_NAME = "notification_db"
    PAYMENT_DB_NAME      = "payment_db"
    STRIPE_SECRET_KEY    = var.stripe_secret_key
  })
}
