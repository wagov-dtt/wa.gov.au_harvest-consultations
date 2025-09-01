group "default" {
  targets = ["test"]
}

group "ci" {
  targets = ["release"]
}

function "platform" {
  params = [arch]
  result = "linux/${arch}"
}

variable "DATE" {
  default = ""
}
variable "REGISTRY" {
  default = "ghcr.io"
}
variable "IMAGE_NAME" {
  default = "wagov-dtt/harvest-consultations"
}
variable "TAGS" {
  default = "harvest-consultations:latest"
}

variable "GITHUB_REF_NAME" {
  default = ""
}

variable "GITHUB_EVENT_NAME" {
  default = ""
}

function "tags" {
  params = [tags_string]
  result = [for tag in split("\n", tags_string) : trim(tag, " \t") if trim(tag, " \t") != ""]
}

function "release_tags" {
  params = []
  result = compact([
    equal(GITHUB_REF_NAME, "main") ? "${REGISTRY}/${IMAGE_NAME}:latest" : "",
    equal(GITHUB_EVENT_NAME, "schedule") ? "${REGISTRY}/${IMAGE_NAME}:nightly" : "",
    notequal(GITHUB_REF_NAME, "") ? "${REGISTRY}/${IMAGE_NAME}:${GITHUB_REF_NAME}" : ""
  ])
}

variable "ARCH" {
  default = "amd64"
}

target "base" {
  args = {
    DATE = "${DATE}"
  }
  labels = {
    "org.opencontainers.image.title" = "harvest-consultations"
    "org.opencontainers.image.description" = "Harvest consultations with sqlmesh"
    "org.opencontainers.image.vendor" = "wagov-dtt"
    "org.opencontainers.image.source" = "https://github.com/wagov-dtt/wa.gov.au_harvest-consultations"
    "org.opencontainers.image.licenses" = "Apache-2.0"
  }
  secret     = ["id=GITHUB_TOKEN,env=GITHUB_TOKEN"]
  provenance = true
  sbom       = true
}

# Local development - native platform only
target "test" {
  inherits = ["base"]
  tags     = ["harvest-consultations:test"]
}

# CI matrix builds - single platform for testing and caching
target "build-test" {
  inherits   = ["base"]
  platforms  = [platform(ARCH)]
  tags       = notequal(TAGS, "harvest-consultations:latest") && notequal(TAGS, "") ? tags(TAGS) : ["harvest-consultations:test"]
  cache-from = ["type=gha,scope=${ARCH}"]
  cache-to   = ["type=gha,mode=max,scope=${ARCH}"]
}

# CI release - multi-platform with cache from native builds
target "release" {
  inherits   = ["base"]
  platforms  = [platform("amd64"), platform("arm64")]
  tags       = notequal(TAGS, "harvest-consultations:latest") ? tags(TAGS) : release_tags()
  attestations = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
  cache-from = [
    "type=gha,scope=amd64",
    "type=gha,scope=arm64"
  ]
}
