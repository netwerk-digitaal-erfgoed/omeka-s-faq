#
# This image uses 2 interstage and an php:7.3-apache final stage
#
# Interstages are:
#   - composer
#   - npm & yarn & grunt
#
# Final stage gets all that generated stuff and add it to the final image
#

############################
#=== composer interstage ===
############################
FROM composer:latest as composer
WORKDIR /app

#=== Get PMF source code ===
ARG PMF_BRANCH="3.2"
RUN set -x \
 && git clone \
        --depth 1 \
        -b $PMF_BRANCH \
        https://github.com/thorsten/phpMyFAQ.git \
        /app

#=== Call composer ===
RUN set -x \
  && composer install --no-dev --ignore-platform-req=ext-gd

#=== Copy and configure custom template ===

COPY omeka-s /app/phpmyfaq/assets/themes/omeka-s

RUN set -x \
 && sed -ri webpack.config.js \
      -e "s~themes\/default\/scss~themes\/omeka-s\/scss~"

########################
#=== yarn interstage ===
########################

FROM node:18-alpine AS builder
WORKDIR /app

RUN apk add --no-cache python3 make g++

COPY --from=composer /app /app

#=== disable cookie-consent, because no tracking
RUN set -x \
 && sed -ri phpmyfaq/assets/src/frontend.js \
      -e "s~import './utils/cookie-consent~// import './utils/cookie-consent~"

RUN yarn install --production 
RUN yarn add webpack 
RUN yarn build

#################################
#=== Final stage with payload ===
#################################
FROM php:8.1-apache

#=== Install gd php dependencie ===
RUN set -x \
 && buildDeps="zlib1g-dev libpng-dev libjpeg-dev libfreetype6-dev" \
 && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
 && docker-php-ext-configure gd --with-freetype=/usr/include/ \
 && docker-php-ext-install gd \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== Install ldap php dependencie ===
#RUN set -x \
# && buildDeps="libldap2-dev" \
# && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
# \
# && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
# && docker-php-ext-install ldap \
# \
# && apt-get purge -y ${buildDeps} \
# && rm -rf /var/lib/apt/lists/*

#=== Install intl, opcache, and zip php dependencie ===
RUN set -x \
 && buildDeps="libicu-dev zlib1g-dev libxml2-dev libzip-dev" \
 && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
 \
 && docker-php-ext-configure intl \
 && docker-php-ext-install intl \
 && docker-php-ext-install zip \
 && docker-php-ext-install opcache \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== Install mysqli php dependency ===
RUN set -x \
 && docker-php-ext-install mysqli

#=== Install pgsql dependency ===
#RUN set -ex \
# && buildDeps="libpq-dev" \
# && apt-get update && apt-get install -y $buildDeps \
# \
# && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
# && docker-php-ext-install pdo pdo_pgsql pgsql \
# \
# && apt-get purge -y ${buildDeps} \
# && rm -rf /var/lib/apt/lists/*

#=== Apache vhost ===
RUN { \
  echo '<VirtualHost *:80>'; \
  echo 'DocumentRoot /var/www/html'; \
  echo; \
  echo '<Directory /var/www/html>'; \
  echo '\tOptions -Indexes'; \
  echo '\tAllowOverride all'; \
  echo '</Directory>'; \
  echo '</VirtualHost>'; \
 } | tee "$APACHE_CONFDIR/sites-available/app.conf" \
 && set -x \
 && a2ensite app \
 && a2dissite 000-default \
 && echo "ServerName localhost" >> $APACHE_CONFDIR/apache2.conf

#=== Apache security ===
RUN { \
  echo 'ServerTokens Prod'; \
  echo 'ServerSignature Off'; \
  echo 'TraceEnable Off'; \
  echo 'Header set X-Content-Type-Options: "nosniff"'; \
  echo 'Header set X-Frame-Options: "sameorigin"'; \
 } | tee $APACHE_CONFDIR/conf-available/security.conf \
 && set -x \
 && a2enconf security

#=== php default ===
ENV PMF_TIMEZONE="Europe/Berlin" \
    PMF_ENABLE_UPLOADS=On \
    PMF_MEMORY_LIMIT=64M \
    PMF_DISABLE_HTACCESS="" \
    PHP_LOG_ERRORS=On \
    PHP_ERROR_REPORTING=E_ALL\
    PHP_POST_MAX_SIZE=64M \
    PHP_UPLOAD_MAX_FILESIZE=64M

#=== Add source code from previously built interstage ===
COPY --from=builder /app/phpmyfaq .

#=== Ensure debug mode is disabled and do some other stuff over the code ===
RUN set -x \
 && sed -ri ./src/Bootstrap.php \
      -e "s~define\('DEBUG', true\);~define\('DEBUG', false\);~" \
 && mv ./config ../saved-config

#=== temp NL language fixes
# to be tackled via https://github.com/thorsten/phpMyFAQ/commit/4780fb8d5c85d06016cf85f1b7706469d4d9b4de
# via https://github.com/thorsten/phpMyFAQ/pull/2494 plus some presentation patches
RUN set -x \
 && sed -ri ./lang/language_nl.php \
      -e "s~'verwante artikelen~Verwante artikelen~" \
 && sed -ri ./lang/language_nl.php \
      -e "s~return $PMF_LANG~\$PMF_LANG\['msgGoToCategory'\] = 'Ga naar categorie';\n\nreturn $PMF_LANG~" \
 && sed -ri ./src/phpMyFAQ/Faq.php \
      -e "s~Utils::makeShorterText..row..question.., 8.~\$row['question']~" \
 && sed -ri ./src/phpMyFAQ/Helper/SearchHelper.php \
      -e "s~<li><i class=.fa fa-question-circle.></i>~<li>~" \
 && sed -ri ./index.php \
      -e "s~title = ' - ' . System::getPoweredByString..~title = ''~"

#=== Set custom entrypoint ===
COPY docker-entrypoint.sh /entrypoint
RUN chmod +x /entrypoint
ENTRYPOINT [ "/entrypoint" ]

#=== Re-Set CMD as we changed the default entrypoint ===
CMD [ "apache2-foreground" ]
