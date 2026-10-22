variable "zone" {
  type = string
}

variable "manage_template" {
  description = "Register the template if it is missing. When false the template is only looked up."
  type        = bool
}

variable "template_bucket" {
  description = "Name of the bucket where template images are stored."
  type        = string
}

variable "template_name" {
  description = "Template name. Empty falls back to rhcos-<release> of the matching RHCOS build."
  type        = string
}

variable "template_disk_size" {
  description = "Disk size in GB the image is resized to before registration."
  type        = number
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "api_secret" {
  type      = string
  sensitive = true
}
