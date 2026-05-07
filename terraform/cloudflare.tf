data "http" "cloudflare_ips" {
  count = var.environment == "local" ? 0 : 1

  url = "https://api.cloudflare.com/client/v4/ips"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  trusted_proxy_ips = (
    var.environment == "local"
    ? [
      "127.0.0.1/32",
      "::1/128",
      "172.16.0.0/12",
    ]
    : concat(
      jsondecode(data.http.cloudflare_ips[0].response_body).result.ipv4_cidrs,
      jsondecode(data.http.cloudflare_ips[0].response_body).result.ipv6_cidrs
    )
  )

  traefik_trusted_proxy_ips = join(",", local.trusted_proxy_ips)
}
