# Internal NLB for the Kubernetes API. Kept internal: the apiserver is only
# reachable from this VPC, the peered VPCs (Argo CD / Jenkins) and the VPN pool.
resource "aws_lb" "api" {
  name                             = "${var.project_name}-api-${var.environment}"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.private_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-api-${var.environment}"
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project_name}-api-${var.environment}"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "6443"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-api-${var.environment}"
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# Public NLB in front of the Traefik NodePorts (replaces the Kind host-nodeport-proxy).
resource "aws_lb" "web" {
  name               = "${var.project_name}-web-${var.environment}"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [var.web_nlb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.project_name}-web-${var.environment}"
  }
}

resource "aws_lb_target_group" "web_http" {
  name        = "${var.project_name}-web-http-${var.environment}"
  port        = var.http_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-web-http-${var.environment}"
  }
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_http.arn
  }
}

resource "aws_lb_target_group" "web_https" {
  name        = "${var.project_name}-web-https-${var.environment}"
  port        = var.https_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-web-https-${var.environment}"
  }
}

resource "aws_lb_listener" "web_https" {
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_https.arn
  }
}

resource "aws_lb_target_group" "extra" {
  for_each = var.extra_listeners

  name        = "${var.project_name}-p${each.key}-${var.environment}"
  port        = each.value
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-p${each.key}-${var.environment}"
  }
}

resource "aws_lb_listener" "extra" {
  for_each = var.extra_listeners

  load_balancer_arn = aws_lb.web.arn
  port              = tonumber(each.key)
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extra[each.key].arn
  }
}
