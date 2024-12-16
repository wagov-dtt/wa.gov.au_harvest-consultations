# Install project tools
prereqs:
  brew bundle install

# Build container images
build: prereqs
  nixpacks build . -t harvest-consultations -s "sqlmesh plan --auto-apply --run --verbose"
