# Single data structure to unify bucket attributes.
locals {
  # Variable-based bucket naming source for IAM/object viewer bindings.
  standard_bucket_names = sort(keys(var.data_buckets_map))
}
