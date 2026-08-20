output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "container_registry" {
  value = azurerm_container_registry.this.login_server
}

output "database_host" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "creator_store_workload_identity_client_id" {
  value = azurerm_user_assigned_identity.creator_store.client_id
}
