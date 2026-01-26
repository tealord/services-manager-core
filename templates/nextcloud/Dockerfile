FROM nextcloud:latest

# Install additional PHP extensions that might be useful for Nextcloud
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libmagickwand-dev \
    procps \
    smbclient \
    supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install exif
RUN docker-php-ext-enable imagick

# Set recommended PHP settings
RUN { \
        echo 'memory_limit=512M'; \
        echo 'upload_max_filesize=10G'; \
        echo 'post_max_size=10G'; \
        echo 'max_execution_time=300'; \
        echo 'max_input_time=300'; \
    } > /usr/local/etc/php/conf.d/nextcloud-recommended.ini

# Add custom configuration if needed
#COPY config/* /usr/src/nextcloud/config/

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html

# Expose ports
EXPOSE 80

# Set volume mount points
VOLUME /var/www/html