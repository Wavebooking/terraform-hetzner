resource "hcloud_ssh_key" "ssh_key_for_hetzner" {
  name       = "ssh-key-for-hetzner"
  public_key = file("~/.ssh/hetzner.pub")
}

locals {
  network_environments = flatten([
    for customer, envs in var.configurations :
    [
      for env, config in envs :
      {
        customer    = customer
        environment = env
        region      = config.region
        subnet      = config.subnet
      }
    ]
  ])
}

resource "hcloud_network" "network" {
  name     = "tourrise-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "network_subnet" {
  for_each = {
    for env in local.network_environments :
    format("%s-%s", env.customer, env.environment) => env
  }

  type         = "cloud"
  network_id   = hcloud_network.network.id
  network_zone = "eu-central"
  ip_range     = each.value.subnet
}

locals {
  web_environments = flatten([
    for customer, envs in var.configurations :
    [
      for env, config in envs :
      [
        for idx in range(config.web_server_count) :
        {
          name         = idx == 0 ? format("%s-%s-web", customer, env) : format("%s-%s-web-%d", customer, env, idx)
          customer     = customer
          environment  = env
          index        = idx
          region       = config.region
          server_type  = config.server_type
          ip           = format("%s%d", replace(config.subnet, "0/24", ""), idx + 2)
          network_name = format("%s-%s", customer, env)
        }
      ]
    ]
  ])

  accessory_environments = flatten([
    for customer, envs in var.configurations :
    [
      for env, config in envs :
      [
        for idx in range(config.accessory_count) :
        {
          name         = idx == 0 ? format("%s-%s-accessories", customer, env) : format("%s-%s-accessories-%d", customer, env, idx)
          customer     = customer
          environment  = env
          index        = idx
          region       = config.region
          server_type  = config.server_type
          ip           = format("%s%d", replace(config.subnet, "0/24", ""), idx + var.configurations[customer][env].web_server_count + 2)
          network_name = format("%s-%s", customer, env)
        }
      ]
    ]
  ])
}

resource "hcloud_server" "web" {
  for_each = {
    for env in local.web_environments :
    env.name => env
  }

  name        = each.value.name
  image       = var.operating_system
  server_type = each.value.server_type
  location    = each.value.region

  labels = {
    ssh         = "yes"
    http        = "yes"
    customer    = each.value.customer
    environment = each.value.environment
    role        = "web"
  }

  user_data = data.cloudinit_config.cloud_config_web.rendered

  network {
    network_id = hcloud_network.network.id
    ip         = each.value.ip
  }

  ssh_keys = [
    hcloud_ssh_key.ssh_key_for_hetzner.id
  ]

  depends_on = [
    hcloud_network.network
  ]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

resource "hcloud_server" "accessories" {
  for_each = {
    for env in local.accessory_environments :
    env.name => env
  }

  name        = each.value.name
  image       = var.operating_system
  server_type = each.value.server_type
  location    = each.value.region

  labels = {
    http        = "no"
    ssh         = "no"
    customer    = each.value.customer
    environment = each.value.environment
    role        = "accessories"
  }

  user_data = data.cloudinit_config.cloud_config_accessories.rendered

  network {
    network_id = hcloud_network.network.id
    ip         = each.value.ip
  }

  ssh_keys = [
    hcloud_ssh_key.ssh_key_for_hetzner.id
  ]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  depends_on = [
    hcloud_network.network
  ]
}

resource "hcloud_load_balancer" "web_load_balancer" {
  for_each = {
    for env in local.web_environments :
    format("%s-%s", env.customer, env.environment) => env
    if env.index == 0 && length([for we in local.web_environments : we if we.customer == env.customer && we.environment == env.environment]) > 1
  }

  name               = format("%s-%s-load-balancer", each.value.customer, each.value.environment)
  load_balancer_type = "lb11"
  location           = each.value.region

  labels = {
    customer    = each.value.customer
    environment = each.value.environment
  }
}

resource "hcloud_load_balancer_target" "load_balancer_target" {
  for_each = hcloud_load_balancer.web_load_balancer

  load_balancer_id = each.value.id
  type             = "label_selector"
  label_selector   = format("http=yes,customer=%s,environment=%s", each.value.labels.customer, each.value.labels.environment)
}

resource "hcloud_load_balancer_service" "load_balancer_service" {
  for_each = hcloud_load_balancer.web_load_balancer

  load_balancer_id = each.value.id
  protocol         = "http"

  http {
    sticky_sessions = true
  }

  health_check {
    protocol = "http"
    port     = 80
    interval = 10
    timeout  = 5

    http {
      path         = "/up"
      response     = "OK"
      tls          = true
      status_codes = ["200"]
    }
  }
}

resource "hcloud_load_balancer_network" "load_balancer_network" {
  for_each = hcloud_load_balancer.web_load_balancer

  load_balancer_id = each.value.id
  network_id       = hcloud_network.network.id
  ip               = replace(hcloud_network_subnet.network_subnet[format("%s-%s", each.value.labels.customer, each.value.labels.environment)].ip_range, "0/24", "255")

  depends_on = [
    hcloud_network.network
  ]
}

resource "hcloud_firewall" "block_all_except_ssh" {
  name = "allow-ssh"
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  apply_to {
    label_selector = "ssh=yes"
  }
}

resource "hcloud_firewall" "allow_http_https" {
  name = "allow-http-https"
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  apply_to {
    label_selector = "http=yes"
  }
}

resource "hcloud_firewall" "block_all_inbound_traffic" {
  name = "block-inbound-traffic"
  # Empty rule blocks all inbound traffic
  apply_to {
    label_selector = "ssh=no"
  }
}
