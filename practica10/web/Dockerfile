FROM nginx:alpine

# Eliminar firma del servidor
RUN sed -i 's/server_tokens on/server_tokens off/' /etc/nginx/nginx.conf; \
    sed -i 's/^user/#user/' /etc/nginx/nginx.conf

# Crear usuario no administrativo
RUN adduser -D -H -u 1001 webuser

# Dar permisos a nginx sobre carpetas de caché
RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

# Copiar archivos web
COPY html/ /usr/share/nginx/html/

# Ajustar permisos
RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

USER nginx