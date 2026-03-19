#!/bin/bash

echo "diagnostico de sistema"
echo ""
echo "hostname : $(cat /etc/hostname)"
echo ""
echo "direccion IP:"
ip -4 addr show | grep inet | grep -v 127.0.0.1
echo ""
echo "Espacio en Disco:"
df -h / | grep -v Filesystem