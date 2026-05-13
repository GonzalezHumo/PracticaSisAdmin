#!/bin/bash
while true; do
    sleep 86400
    PGPASSWORD=$POSTGRES_PASSWORD pg_dump -U $POSTGRES_USER $POSTGRES_DB > /backups/backup_$(date +%Y%m%d_%H%M%S).sql
    echo "Respaldo realizado: $(date)"
done