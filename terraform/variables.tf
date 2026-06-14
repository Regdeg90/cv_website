# terraform/variables.tf

variable "domain_name" {
  type = string
  # example: "cv.example.com"
}

variable "hosted_zone_name" {
  type = string
  # example: "example.com"
}

variable "environment" {
  type = string
}