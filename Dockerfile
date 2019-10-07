FROM ubuntu:18.04
MAINTAINER Bernhard Steindl <git@e9a.at>
# Based on LaraEdit
# IntElect-Docker v2

# set some environment variables
ENV APP_NAME intelect
ENV APP_EMAIL git@e9a.at
ENV APP_DOMAIN intelect.local
ENV DEBIAN_FRONTEND noninteractive

# upgrade the container
RUN apt-get update && \
    apt-get upgrade -y

# install some prerequisites
RUN apt-get install -y curl libmcrypt4 memcached \
    wget \
    debconf-utils locales

# set the locale
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale  && \
    locale-gen en_US.UTF-8  && \
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    
# copy requirements
COPY .bash_aliases /root

# install nginx
RUN apt-get install -y --force-yes nginx
COPY intelect /etc/nginx/sites-available/
RUN rm -rf /etc/nginx/sites-available/default && \
    rm -rf /etc/nginx/sites-enabled/default && \
    ln -fs "/etc/nginx/sites-available/intelect" "/etc/nginx/sites-enabled/intelect" && \
    sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf && \
    sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf && \
    echo "daemon off;" >> /etc/nginx/nginx.conf && \
    usermod -u 1000 www-data && \
    sed -i -e"s/worker_processes  1/worker_processes 5/" /etc/nginx/nginx.conf


# install php
RUN apt-get install -y --force-yes php-fpm php-cli php-dev php-pgsql php-sqlite3 php-gd \
    php-apcu php-curl php-imap php-mysql php-readline php-xdebug php-common \
    php-mbstring php-xml php-zip
RUN sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.2/cli/php.ini && \
    sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.2/cli/php.ini && \
    sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.2/cli/php.ini && \
    sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.2/fpm/php.ini && \
    sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.2/fpm/php.ini && \
    sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.2/fpm/php.ini && \
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/7.2/fpm/php.ini && \
    sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/7.2/fpm/php.ini && \
    sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.2/fpm/php.ini && \
    sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/7.2/fpm/php-fpm.conf && \
    sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/pm.max_children = 5/pm.max_children = 9/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    sed -i -e "s/;listen.mode = 0660/listen.mode = 0750/g" /etc/php/7.2/fpm/pool.d/www.conf && \
    find /etc/php/7.2/cli/conf.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;
COPY fastcgi_params /etc/nginx/
RUN mkdir -p /run/php/ && chown -Rf www-data.www-data /run/php

# install mysql 
RUN echo mysql-server mysql-server/root_password password $DB_PASS | debconf-set-selections;\
    echo mysql-server mysql-server/root_password_again password $DB_PASS | debconf-set-selections;\
    apt-get install -y mysql-server && \
    echo "[mysqld]" >> /etc/mysql/my.cnf && \
    echo "default_password_lifetime = 0" >> /etc/mysql/my.cnf && \
    sed -i '/^bind-address/s/bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf
RUN service mysql start & \
    sleep 10s && \
    echo "GRANT ALL ON *.* TO root@'0.0.0.0' IDENTIFIED BY '4Mhb3Yhowjgo9uEsUmJZwTWMCyFTEV' WITH GRANT OPTION; CREATE USER 'intelect-user'@'0.0.0.0' IDENTIFIED BY '5G7XC4bhNw92GGccjpfVQbS'; GRANT ALL ON *.* TO 'intelect-user'@'0.0.0.0' IDENTIFIED BY '5G7XC4bhNw92GGccjpfVQbS' WITH GRANT OPTION; GRANT ALL ON *.* TO 'intelect-user'@'%' IDENTIFIED BY '5G7XC4bhNw92GGccjpfVQbS' WITH GRANT OPTION; FLUSH PRIVILEGES; CREATE DATABASE intelect;" | mysql
VOLUME ["/var/lib/mysql"]

# install composer
RUN curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer && \
    printf "\nPATH=\"~/.composer/vendor/bin:\$PATH\"\n" | tee -a ~/.bashrc
# install laravel envoy
RUN composer global require "laravel/envoy"

#install laravel installer
RUN composer global require "laravel/installer"

# install supervisor
RUN apt-get install -y supervisor redis-server cron && \
    mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# VOLUME ["/var/log/supervisor"]

RUN apt-get install -y --force-yes beanstalkd && \
    sed -i "s/BEANSTALKD_LISTEN_ADDR.*/BEANSTALKD_LISTEN_ADDR=0.0.0.0/" /etc/default/beanstalkd && \
    sed -i "s/#START=yes/START=yes/" /etc/default/beanstalkd && \
    /etc/init.d/beanstalkd start

# clean up our mess
RUN apt-get autoremove -y && \
    apt-get clean && \
    apt-get autoclean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/man/?? && \
    rm -rf /usr/share/man/??_*


# Set environment for IntElect
#COPY intelect-devel /var/www/html/intelect
VOLUME ["/var/www/html/intelect"]
RUN chown -Rf www-data:www-data /var/www/html/
#RUN cd /var/www/html/intelect && composer update 
#RUN service mysql start && cd /var/www/html/intelect && composer install && php artisan key:generate && php artisan migrate && cat /var/www/html/intelect/app/database_init.sql | mysql --user=intelect-user --password=5G7XC4bhNw92GGccjpfVQbS


# expose ports
EXPOSE 80 3306 6379

# set container entrypoints
ENTRYPOINT ["/bin/bash","-c"]
CMD ["/usr/bin/supervisord"]
