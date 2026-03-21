FROM nginx:1.25-alpine
# nginxがrootやtry_filesを解決するためにpublicディレクトリが必要
COPY src/public /var/www/html/public
COPY docker/nginx/default-ecs.conf /etc/nginx/conf.d/default.conf
