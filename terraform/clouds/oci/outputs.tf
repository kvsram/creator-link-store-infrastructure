output "cluster_id" {
  value = oci_containerengine_cluster.this.id
}

output "cluster_name" {
  value = oci_containerengine_cluster.this.name
}

output "private_kubernetes_endpoint" {
  value = oci_containerengine_cluster.this.endpoints[0].private_endpoint
}

output "database_primary_endpoint" {
  value = data.oci_psql_db_system_connection_detail.this.primary_db_endpoint[0].fqdn
}

output "container_registry_prefix" {
  value = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.this.namespace}"
}

output "vcn_id" {
  value = oci_core_vcn.this.id
}
