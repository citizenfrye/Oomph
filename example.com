# Redirect HTTP -> HTTPS
server {
    listen 80;
    server_name www.example.com example.com;

    include snippets/letsencrypt.conf;
    return 301 https://example.com$request_uri;
}

# Redirect WWW -> NON WWW
server {
    listen 443 ssl http2;
    server_name www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    include snippets/ssl.conf;

    return 301 https://example.com$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com;

    root /var/www/my_drupal/web;

    # SSL parameters
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    include snippets/ssl.conf;

    # log files
    access_log /var/log/nginx/example.com.access.log;
    error_log /var/log/nginx/example.com.error.log;

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~ \..*/.*\.php$ {
        return 403;
    }

    location ~ ^/sites/.*/private/ {
        return 403;
    }

    # Block access to scripts in site files directory
    location ~ ^/sites/[^/]+/files/.*\.php$ {
        deny all;
    }

    # Block access to "hidden" files and directories whose names begin with a
    # period. This includes directories used by version control systems such
    # as Subversion or Git to store control files.
    location ~ (^|/)\. {
        return 403;
    }

    location / {
        try_files $uri /index.php?$query_string;
    }

    location @rewrite {
        rewrite ^/(.*)$ /index.php?q=$1;
    }

    # Don't allow direct access to PHP files in the vendor directory.
    location ~ /vendor/.*\.php$ {
        deny all;
        return 404;
    }


    location ~ '\.php$|^/update.php' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
        include fastcgi_params;
        # Block httpoxy attacks. See https://httpoxy.org/.
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param QUERY_STRING $query_string;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:/run/php-fpm/www.sock;
    }

    # Fighting with Styles? This little gem is amazing.
    # location ~ ^/sites/.*/files/imagecache/ { # For Drupal <= 6
    location ~ ^/sites/.*/files/styles/ { # For Drupal >= 7
        try_files $uri @rewrite;
    }

    # Handle private files through Drupal. Private file's path can come
    # with a language prefix.
    location ~ ^(/[a-z\-]+)?/system/files/ { # For Drupal >= 7
        try_files $uri /index.php?$query_string;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        try_files $uri @rewrite;
        expires max;
        log_not_found off;
    }

}
