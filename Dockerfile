# Docker ldap proxy (with readonly access too)
# based on mrbobbytables/dockproxy
#
# VERSION   2.0.0
#
# CREATED ON Mon Feb 21 22:16:15 UTC 2016
#

FROM ubuntu:14.04

MAINTAINER mrbobbytables, Dmitrii Zolotov <dzolotov@herzen.spb.ru>

RUN apt-get update

#DEBIAN_FRONTEND=noninteractive is used to suppress prompts for libpam-ldapd
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install -y nginx-extras \
    libpam-ldapd \
    supervisor && apt-get clean && rm -rf /var/lib/apt/lists/*

#Copy configs to their needed locations
COPY init.sh ./init.sh
COPY ./nslcd/nslcd.conf /etc/nslcd.conf
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/ssl/ /etc/nginx/ssl/
COPY ./supervisor/dockproxy.conf /etc/supervisord/conf.d/dockproxy.conf

# nslcd will complain about nslcd.conf being world-readable if permissions are not restricted.
# /etc/pam.d/nginx contains the ldap auth config for nginx
RUN chmod 640 /etc/nslcd.conf && \
    chmod +x init.sh && \
    echo 'auth\trequired\tpam_ldap.so\naccount\trequired\tpam_ldap.so' >> /etc/pam.d/nginx && \
    rm /etc/nginx/sites-enabled/* && rm /etc/nginx/sites-available/*

ENV DOCKREG http://registry:5000

EXPOSE 80 443

CMD ["./init.sh"]
