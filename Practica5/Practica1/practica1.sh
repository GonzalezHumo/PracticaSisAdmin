#!/bin/bash

echo "Hostname:"
hostnamectl hostname

echo ""
echo "Direccion IP Actual:"
ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}'

echo ""
echo "Espacio En Disco:"
df -h / | awk 'NR==2 {printf "Used: %s\tFree: %s\n", $3, $4}'