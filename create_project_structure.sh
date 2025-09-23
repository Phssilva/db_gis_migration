#!/bin/bash

# Create main project directories
mkdir -p config
mkdir -p scripts/pre_migration
mkdir -p scripts/migration
mkdir -p scripts/post_migration
mkdir -p scripts/validation
mkdir -p scripts/rollback
mkdir -p docs
mkdir -p logs
mkdir -p backups

# Create placeholder files to ensure git tracks empty directories
touch config/.gitkeep
touch scripts/pre_migration/.gitkeep
touch scripts/migration/.gitkeep
touch scripts/post_migration/.gitkeep
touch scripts/validation/.gitkeep
touch scripts/rollback/.gitkeep
touch docs/.gitkeep
touch logs/.gitkeep
touch backups/.gitkeep

echo "Project structure created successfully!"
