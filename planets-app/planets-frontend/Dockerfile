# Use the nginx:alpine base image
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Copy static assets
COPY . /usr/share/nginx/html

# Add runtime entrypoint script for injecting API base URL
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
	&& mkdir -p /usr/share/nginx/html/config

# Environment variable that can be overridden at deploy time (in Container Apps env vars)
ENV API_BASE_URL=""

EXPOSE 80

# Use custom entrypoint to generate runtime config then start nginx
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]