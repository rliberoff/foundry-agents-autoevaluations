data "azurerm_monitor_diagnostic_categories" "this" {
  for_each = var.target_resource_ids

  resource_id = each.value
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.target_resource_ids

  name                       = "diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.this[each.key].log_category_types)

    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.this[each.key].metrics)

    content {
      category = enabled_metric.value
    }
  }
}
