# Dockproxy

Dockproxy is a nginx based proxy container meant to be placed in front of the docker-registry.

This build integrates http auth via the [Auth PAM](http://web.iti.upv.es/~sto/nginx/) module available in the nginx-extras package.

Additional this fork includes read-only (w/o authentication) server on port 80

Configuration files 

### Contents
 * [Configuration and Usage](#configuration-and-Usage)
  * [TL;DR](#tldr)
  * [LDAP Config](#ldap-config)
  * [SSL Cert Generation](#ssl-cert-generation)
  * [Usage](#usage)
 * [Troubleshooting](#troubleshooting)
  * [Authentication Errors](#authentication-errors)
  * [Proxy Errors](#proxy-errors)
 * [Advanced Configuration and Tuning](#advanced-configuration-and-tuning)
  * [Nginx-lua](#nginx-lua)
  * [Worker and Connection Tuning](#worker-and-connection-tuning)

---



## Configuration and Usage

#### TL;DR

1. Adjust ldap conf in `nslcd/nslcd.conf` or override with docker volume
2. Bind ssl certificates via docker volume (for ex. --volume=/etc/server.crt:/etc/nginx/ssl/dockproxy.crt)
3. Build and take your pick of executing the following:
 * If not using a linked container:
`docker run -d -p 443:443 -e REG_ADDR=[registry_address] -e REG_PRT=[registry_port] dockproxy`
 * If using a linked container:
`docker run -d -p 443:443 --link docker-registry:DOCKREG dockproxy`

By default, search is disabled. To enable it, add the following environmental variable to your docker run command:

`-e REG_SEARCH=enabled`

----------


I just need to get this out of the way:

Before building the image the ldap config must be modified and new ssl certs generated.


#### LDAP Config
The file `nslcd/nslcd.conf` requires several base settings to work correctly. What is included in the example configuration is the minimum requirements needed for nginx to authenticate users against Active Directory. For alternate configurations or further information please see the Arthur de Jong's [nss-pam-ldapd repo](https://github.com/arthurdejong/nss-pam-ldapd).

##### Example Configuration:

###### For AD:
```
uid nslcd
gid nslcd

ldap_version 3
tls_reqcert never
ignorecase yes
referrals no

uri ldaps://example.com
base dc=example,dc=com
binddn cn=imauser,cn=users,dc=example,dc=com
bindpw imasecret

filter passwd (objectClass=user)
map    passwd    uid    sAMAccountName
 
filter shadow (objectClass=user)
map    shadow    uid    sAMAccountName
```

* `uri` - The LDAP uri. Most likely `uri ldaps://yourdomaincontrollerhere`
* `base` - The base DN used as the search base.
* `binddn` - the user account used to do the authentication
* `bindpw` - The password for the accout used in the `binddn` statement.
*  `filter passwd` and `filter shadow` - You can restrict access to specific groups using these statements. If you wish to allow all authenticated users, the defaults are sufficient. Otherwise, restricting it to a specific group would be something along the lines of:

```
filter passwd (&(objectClass=user)(memberOf=cn=DockerUsers,ou=Groups,dc=example,dc=com))
map    passwd    uid    sAMAccountName

filter shadow (&(objectClass=user)(memberOf=cn=DockerUsers,ou=Groups,dc=example,dc=com))
map    shadow    uid    sAMAccountName
```
* `map passwd` and `map shadow` - For Active Directory, just leave these to the default map to `sAMAccountName`



###### For OpenLDAP:
```
uid nslcd
gid nslcd

ldap_version 3
tls_reqcert neves
ignorecase yes
referrals no

uri ldaps://example.com
base dc=example,dc=com
binddn cn=imauser,cn=users,dc=example,dc=com
bindpw imasecret

filter password (&(objectClass=posixAccount)(memberof=cn=docker,dc=example,dc=com))
filter shadow (&(objectClass=posixAccount)(memberof=cn=docker,dc=example,dc=com))

----------
#### SSL Config
The nginx config is looking for `dockproxy.key` and `dockproxy.crt`. These should be placed in the `nginx/ssl/` folder when the container is built.

For building and testing purposes, execute the following in the dockproxy folder to generate a cert:

`openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx/ssl/dockproxy.key -out nginx/ssl/dockproxy.crt`

----------
#### Usage

Usage is pretty simple. After building the container with the needed config changes. Just execute the following:

`docker run -d -p 80:80 -p 443:443 -e REG_ADDR=[registry_address] -e REG_PRT=[registry_port] dockproxy`

or

`docker run -d -p 80:80 -p 443:443 -e REG_ADDR=[registry_address] -e REG_PRT=[registry_port] -e REG_SEARCH=enabled dockproxy`

if you wish to enable searching of the registry.

Where `REG_ADDR` is the IP address of the docker registry, and `REG_PRT` is the port. If you do not set `REG_PRT` it will default to 5000. If you do not set `REG_SEARCH` to `enabled` it will default to `disabled`.

A better option (if running the containers on the same host), is to simply link the containers together with the link alias called `DOCKREG`. The init script will parse the link information and connect to the docker registry.

`docker run -d -p 443:443 -e REG_SEARCH=enabled --link docker-registry:DOCKREG dockproxy`

----------

## Troubleshooting

#### Authentication Errors
Can't get ldap auth working right? Theres a utility to help with that.

Libpam-ldap has a handy debugging mode (`nslcd -d`) for working through these sort of things. Just do the following.

1. Launch the container: `docker run -it -p 443:443 --link docker-registry:DOCKREG dockproxy /bin/bash`
2. start nginx `service nginx start`
3. launch `nslcd -d`

Then attempt to login to the proxy via a browser and watch the output from `nslcd`.


#### Proxy Errors

Did you use a DNS name instead of an IP? If you used a DNS name and it's changed IPs you're gonna have a bad time...

By default nginx does not attempt to re-resolve an address. For this it requires a resolver. Please see the [nginx docs](http://nginx.org/en/docs/http/ngx_http_core_module.html#resolver) for more information, and adjust the config as needed.


----------

## Advanced Configuration and Tuning

#### Nginx-lua

Dockproxy passes the environment variables to Nginx via the [Nginx Lua Module](http://wiki.nginx.org/HttpLuaModule). The Lua module is quite powerful and adds some great flexibility, and to be honest there is significantly more there than I want to cover --so I'll just include a bit on what is used in dockproxy: Passing Environment variables.

If there are other environment variables that you wish to pass, the main thing to remember is that they must first be declared in `nginx/nginx.conf` in the form of `ENV [environment variable name];` e.g.:

```
ENV REG_ADDR;
ENV REG_PRT;
```

You can then later set a variable equal to their value via the `set_by_lua` directive. Please note that `set_by_lua` can **ONLY** be used in the `server`, `server if`, `location`, or `location if` context. These can then be used later in the form of `$variable_name`.

Here is an example:

```
server {
    set_by_lua $reg_addr 'return os.getenv("REG_ADDR")';
    set_by_lua $reg_prt 'return os.getenv("REG_PRT")';

    listen 80 default_server;

    location / {
    proxy_pass http://$reg_addr:$reg_prt;
    }
 }
```

After you do all that, the supervisord config at `supervisor/dockproxy.conf` will need to be modified. Add any extra envirment variables to the `environment` config using the format of `%(ENV_[env var name])s`. Here is an example from the config:

`environment=REG_ADDR=%(ENV_REG_ADDR)s`


For further supervisord config information, please see the docs here: http://supervisord.org

----------
#### Worker and Connection Tuning

To be honest, I haven't taken the time to sit down with wireshark and watch how many connection a docker image pull can initiate, but in general you want to have 1 `worker_process` per core. Normally, it's about 2 worker connections per user at point in time. Adjust as needed for your environment. If anyone has any better info, please pass it along.



