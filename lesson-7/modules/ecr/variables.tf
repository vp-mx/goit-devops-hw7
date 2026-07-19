variable "ecr_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "scan_on_push" {
  description = "Whether to scan images for vulnerabilities on push"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "force_delete" {
  description = "Allow the repository to be deleted even if it still contains images"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep before the oldest ones expire"
  type        = number
  default     = 10
}
