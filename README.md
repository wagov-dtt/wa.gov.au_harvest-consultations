# SQLMesh Data Pipeline for Drupal Integration
## Overview
This document outlines an hourly process using SQLMesh to harvest data from external REST APIs, transform it, and store it in MySQL for consumption by Drupal views on wa.gov.au. Content ownership is determined by environment variables injected via GitHub Actions self-hosted runners, running near the database instance.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/wagov-dtt/wa.gov.au_harvest-consultations)

Once opened, you can run `sqlmesh ui` in the cli, and open the resultant port in a browser to edit/debug the pipelines.

## Prerequisites

Install brew and aws cli to enable accessing secrets from aws:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo >> ~/.bashrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew bundle install
```

Setup a github actions runner user on a debian box (see [cloudformation-example.yaml](./cloudformation-example.yaml) for an example) that has access to secrets manager and appropriate networking for pipelines

```bash
sudo useradd -m -s /bin/bash ghactions01
sudo usermod -aG sudo ghactions01
echo "%sudo ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/nopasswd
sudo su - ghactions01
# follow github self hosted runner onboarding
# in dir /home/ghactions01/actions-runner
./svc.sh install ghactions01
./svc.sh start
```

## Workflow Diagram
```mermaid
graph TD
    subgraph "Data Pipeline"
        GH[GitHub Actions] -->|Inject ENV vars| A
        A[External REST APIs] -->|Hourly Harvest| B[SQLMesh]
    end
    subgraph "Content Management"
        B -->|Deduplicate| DB
        DB[(MySQL Databases<br>- drupal<br>- sqlmesh)]
        DB -->|Content Type Mapping| E[Drupal Views]
        E -->|Render| F[wa.gov.au Website]
        CM[Content Manager] -->|Create/Edit Internal Content| D[Drupal CMS]
        D -->|Store| DB
        D -->|Manage| E
    end
```

## Content Types and Ownership

### Current Content Types
1. **Consultations**
2. **Service Locations**

### Content Ownership Model
- **External Authorship**
  - Source: REST API pipeline
  - Identification: GitHub Actions environment variables
  - Update frequency: Hourly via self-hosted runners
  - Drupal access: Read-only

- **Drupal Authorship**
  - Source: Drupal CMS
  - Identification: Standard Drupal authorship
  - Update frequency: Real-time
  - Drupal access: Full CRUD operations

## Process Steps

1. **Hourly Data Harvesting**: SQLMesh connects to and harvests data from external REST APIs
   - [SQLMesh Python Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/python_models/)
   - Configurable API endpoints and authentication
   - Runs every hour via scheduled task

2. **Data Transformation**: SQLMesh processes the harvested data
   - [SQLMesh SQL Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/sql_models/)
   - Data cleaning and standardization
   - Field mapping to Drupal content types
   - Authorship metadata tagging
   - Deduplication logic

3. **MySQL Integration**: 
   - Direct database loading from SQLMesh
   - Schema compatibility with Drupal requirements
   - Authorship tracking fields
   - Content versioning and updates

4. **Content Management**:
   - Read-only display of external content
   - Full management of Drupal-authored content
   - Content type mapping via Drupal Views
   - Integrated display on wa.gov.au website

## Key Components

### SQLMesh Pipeline
- **Python Models**: Define connections to REST APIs and MySQL output
- **SQL Transformations**: Create standardized data structures
- **Incremental Processing**: Handle hourly updates efficiently
- **Authorship Tagging**: Mark content as externally owned

### Drupal Integration
- **Content Types**: Structured data models for Consultations and Service Locations
- **Views**: Custom data presentations with ownership-aware access
- **Content Management**: User interface for Drupal-authored content

### MySQL Database
- Serves as primary storage for both external and internal content
- Maintains clear ownership designation
- Supports both hourly batch updates and real-time changes
- Enforces read-only access for external content

## Notes on Development
For detailed implementation guidance, refer to:
- [SQLMesh Documentation](https://sqlmesh.com/docs/)
- [Drupal Views Documentation](https://www.drupal.org/docs/user_guide/en/views-chapter.html)
