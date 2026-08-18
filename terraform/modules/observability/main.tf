data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/creator-store/${var.name}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "canary_failures" {
  count               = var.canary_url == "" ? 0 : 1
  alarm_name          = "${var.name}-canary-failure"
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 100
  treat_missing_data  = "breaching"
  dimensions          = { CanaryName = "${var.name}-public" }
  alarm_description   = "Regional public canary has failed twice"
  tags                = var.tags
}

resource "aws_cloudwatch_dashboard" "service" {
  dashboard_name = "${var.name}-service"
  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "Regional canary success"
        view    = "timeSeries"
        region  = data.aws_region.current.name
        metrics = [["CloudWatchSynthetics", "SuccessPercent", "CanaryName", "${var.name}-public"]]
      }
    }]
  })
}
