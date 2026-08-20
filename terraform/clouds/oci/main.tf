locals {
  tags = merge(var.freeform_tags, {
    application = "creator-store"
    environment = var.environment
    managed-by  = "terraform"
  })
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "vcn-${var.name}"
  dns_label      = "creatorstore"
  cidr_blocks    = ["10.42.0.0/16"]
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "igw-${var.name}"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "nat-${var.name}"
  freeform_tags  = local.tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-public-${var.name}"
  freeform_tags  = local.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-private-${var.name}"
  freeform_tags  = local.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "sl-private-${var.name}"
  freeform_tags  = local.tags

  ingress_security_rules {
    protocol = "all"
    source   = "10.42.0.0/16"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "public_lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "sl-public-lb-${var.name}"
  freeform_tags  = local.tags

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "load_balancer" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "snet-lb-${var.name}"
  dns_label                  = "lb"
  cidr_block                 = "10.42.1.0/24"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public_lb.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "workers" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "snet-workers-${var.name}"
  dns_label                  = "workers"
  cidr_block                 = "10.42.10.0/23"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "api" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "snet-api-${var.name}"
  dns_label                  = "api"
  cidr_block                 = "10.42.20.0/24"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "database" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "snet-db-${var.name}"
  dns_label                  = "database"
  cidr_block                 = "10.42.30.0/24"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_ocid
  name               = "oke-${var.name}"
  kubernetes_version = var.kubernetes_version
  vcn_id             = oci_core_vcn.this.id
  type               = "ENHANCED_CLUSTER"
  freeform_tags      = local.tags

  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = oci_core_subnet.api.id
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.load_balancer.id]
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

resource "oci_containerengine_node_pool" "this" {
  compartment_id      = var.compartment_ocid
  cluster_id          = oci_containerengine_cluster.this.id
  name                = "pool-${var.name}"
  kubernetes_version  = var.kubernetes_version
  node_shape          = var.node_shape
  subnet_ids          = [oci_core_subnet.workers.id]
  quantity_per_subnet = var.node_count
  ssh_public_key      = var.node_ssh_public_key
  freeform_tags       = local.tags

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gbs
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.node_image_ocid
    boot_volume_size_in_gbs = 60
  }

  node_pool_cycling_details {
    is_node_cycling_enabled = true
    maximum_surge           = "1"
    maximum_unavailable     = "0"
    cycle_modes             = ["INSTANCE_REPLACE"]
  }
}

resource "oci_containerengine_cluster_workload_mapping" "creator_store" {
  cluster_id            = oci_containerengine_cluster.this.id
  mapped_compartment_id = var.compartment_ocid
  namespace             = "creator-store"
  freeform_tags         = local.tags
}

resource "oci_psql_db_system" "this" {
  compartment_id              = var.compartment_ocid
  display_name                = "psql-${var.name}"
  db_version                  = "16"
  shape                       = "PostgreSQL.VM.Standard.E5.Flex"
  system_type                 = "OCI_OPTIMIZED_STORAGE"
  instance_count              = var.postgres_instance_count
  instance_ocpu_count         = 2
  instance_memory_size_in_gbs = 16
  freeform_tags               = local.tags

  network_details {
    subnet_id                  = oci_core_subnet.database.id
    is_reader_endpoint_enabled = var.postgres_instance_count > 1
  }

  storage_details {
    is_regionally_durable = true
    system_type           = "OCI_OPTIMIZED_STORAGE"
  }

  credentials {
    username = var.postgres_username
    password_details {
      password_type  = "VAULT_SECRET"
      secret_id      = var.postgres_password_secret_ocid
      secret_version = var.postgres_password_secret_version
    }
  }

  management_policy {
    backup_policy {
      kind           = "DAILY"
      backup_start   = "02:00"
      retention_days = var.environment == "prod" ? 35 : 7
    }
    maintenance_window_start = "SUN 03:00"
  }
}

data "oci_psql_db_system_connection_detail" "this" {
  db_system_id = oci_psql_db_system.this.id
}
