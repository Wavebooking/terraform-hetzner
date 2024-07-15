variable "hetzner_api_key" {
  description = "API key for Hetzner Cloud"
  type        = string
}

variable "operating_system" {
  description = "Operating system for the server"
  type        = string
  default     = "ubuntu-24.04"
}
variable "configurations" {
  description = "Configuration for each customer and environment"
  type = map(map(object({
    region           = string
    server_type      = string
    web_server_count = number
    accessory_count  = number
    subnet           = string
  })))
  default = {
    HHT = {
      production = {
        region           = "nbg1"
        server_type      = "cx22"
        web_server_count = 1
        accessory_count  = 1
        subnet           = "10.0.1.0/24"
      }
      staging = {
        region           = "nbg1"
        server_type      = "cx22"
        web_server_count = 1
        accessory_count  = 1
        subnet           = "10.0.0.0/24"
      }
    }
    PRO = {
      production = {
        region           = "nbg1"
        server_type      = "cx22"
        web_server_count = 1
        accessory_count  = 1
        subnet           = "10.0.3.0/24"
      }
      staging = {
        region           = "nbg1"
        server_type      = "cx22"
        web_server_count = 1
        accessory_count  = 1
        subnet           = "10.0.2.0/24"
      }
    }
  }
}
