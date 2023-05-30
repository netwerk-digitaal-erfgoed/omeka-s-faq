# omeka-s-faq

Build Docker containers for the Omeka S FAQ (production) website based on https://github.com/thorsten/phpMyFAQ. 

Cloned from https://github.com/phpMyFAQ/docker-hub and adjusted for newer components and custom theme. No ElasticSearch or phpMyAdmin.

##How to use

To build an image containing the current code in the specified branch:

    git clone https://github.com/netwerk-digitaal-erfgoed/omeka-s-faq.git && cd omeka-s-faq
    git checkout
    docker build -t phpmyfaq .

## To run

Use docker compose:

    docker-compose up

The command above starts 2 containers as following.

_Running using volumes:_
- **mariadb**: image with xtrabackup support

_Running apache web server with PHP support:_
- **phpmyfaq**: mounts the resources folders in `./volumes`.

Then services will be available at following addresses:

- phpMyFAQ: (http://localhost:85)

