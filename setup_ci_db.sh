#!/bin/bash
# CI Database Setup Script
# This script sets up the PostgreSQL database for Elixir tests in CircleCI

set -e

echo "Setting up test database for CircleCI..."

# Create test database
createdb -h localhost -U postgres shot_server_test || echo "Database already exists"

# Load schema from Rails dump
psql -h localhost -U postgres -d shot_server_test < priv/repo/structure.sql || echo "Schema load completed (errors expected if tables exist)"

echo "Database setup complete!"