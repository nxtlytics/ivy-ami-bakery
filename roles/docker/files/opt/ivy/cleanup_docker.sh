#!/bin/bash

echo "cleaning up docker images at $(date)"
docker system prune -af
echo "finished cleaning up docker images at $(date)"