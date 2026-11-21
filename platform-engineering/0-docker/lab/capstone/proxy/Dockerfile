# The capstone's reverse proxy: nginx that never runs as root, with the Alpine packages
# brought up to date at build time, because the base image's scan finds fixed
# vulnerabilities. Rebuild it regularly: apk upgrade takes whatever is current that day.
FROM nginxinc/nginx-unprivileged:1.31.7-alpine3.24
LABEL lab.course="docker"
USER root
RUN apk upgrade --no-cache
COPY nginx.conf /etc/nginx/conf.d/default.conf
USER 101
