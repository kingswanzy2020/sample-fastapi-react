#!/bin/bash

# Exit in case of error
set -e

# Build and run containers. The "migrate" service applies pending migrations
# and docker-compose waits for it to complete before starting "backend".
docker-compose up -d

# Create initial data
docker-compose run --rm backend python3 app/initial_data.py
