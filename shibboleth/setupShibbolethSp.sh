#!/bin/bash

# Setting up a Shibboleth 2 server based on Funsho's notes (see NXBT-946)

# dependencies -> serveur LDAP, java8, tomcat8
# check how containers needing java 8 are built

# TODO finish this script
# TODO make heap Xmx a variable (512m for example?)
# TODO clean installation folders (see /tmp)
# TODO make apache ports for SP a parameter

# NOTE idpparams.patch has to be in the same location than the script
# NOTE NUXEO_CLID has to be setup !!

# NOTE il a fallu
# changer l'entityID de example.org à sp.shibboleth.com dans le relying-party.xml ?
# mettre tout à never dans relying-party.xml
# enlever validate="true" de shibboleth.xml pour le MetadataProvider

# A FAIRE ajouter un BON mapping pour l'uid et l'email dans le SP (/etc/shibboleth/attribute-map.xml)
# urn:oid:0.9.2342.19200300.100.1.1 (IDP)
# urn:oid:0.9.2342.19200300.100.1.1 (SP)
#
# urn:oid:0.9.2342.19200300.100.1.3 (IDP)
# urn:oid:0.9.2342.19200300.100.1.3 (SP)

ORIGIN_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"

SHIB_LDAP_USERS_BASE_DN="dc=nuxeo,dc=com"
SHIB_LDAP_ADMIN_BIND_DN="cn=admin,${SHIB_LDAP_USERS_BASE_DN}"
SHIB_LDAP_ADMIN_BIND_PASSWORD="password"

IDP_HOST="idp.shibboleth.com"
IDP_HOME="/opt/shibboleth-idp"
IDP_STORE_PASS="/opt/shibboleth-idp"
IDP_TOMCAT_FOLDER="tomcat-shib-idp"
IDP_TOMCAT_HOME="/opt/${IDP_TOMCAT_FOLDER}"
IDP_TOMCAT_HTTP_PORT="8080"
# IDP_TOMCAT_HTTPS_PORT="8443"
IDP_TOMCAT_HTTPS_PORT="443"
IDP_TOMCAT_SHUTDOWN_PORT="8006"
IDP_SSL_ENABLED="yes"

# LDAP_HOST="ldap.shibboleth.com"
LDAP_HOST="${IDP_HOST}"
LDAP_CONTAINER="shibboleth_ldap"

SP_HOST="sp.shibboleth.com"
SP_SSL_ENABLED="yes"
SP_TOMCAT_HTTP_PORT="8180"
NUXEO_CONTAINER="shibboleth_nuxeo"
NUXEO_VERSION="7.10"
NUXEO_CLID="22adb138-fa4b-4f10-abb2-46f6ca816056--0894cf15-c745-45fe-b4fd-52422c0e9606"
NUXEO_INSTALL_HOTFIX="yes"

# URL for testing IdP is up
# http://${IDP_HOST}:${IDP_TOMCAT_HTTP_PORT}/idp/Authn/UserPassword
# http://10.213.3.40:8080/idp/Authn/UserPassword

# Shibboleth SP setup [BEGIN]
sudo apt-get install apache2 -y -qq
sudo apt-get install libapache2-mod-shib2 -y -qq
sudo curl -k -O http://pkg.switch.ch/switchaai/SWITCHaai-swdistrib.asc
sudo apt-key add SWITCHaai-swdistrib.asc
echo 'deb http://pkg.switch.ch/switchaai/ubuntu xenial main' | sudo tee /etc/apt/sources.list.d/SWITCHaai-swdistrib.list > /dev/null
sudo apt-get update -y -qq
sudo apt-get install shibboleth -y -qq
sudo shib-keygen

cd /
sudo patch -p0 < "${ORIGIN_FOLDER}/shibboleth2.xml.patch"
sudo sed -i "s/SHIBBOLETH_IDP_PROTOCOL/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
sudo sed -i "s/SHIBBOLETH_SP_PROTOCOL/$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
sudo sed -i "s/SHIBBOLETH_IDP_HOSTNAME/${IDP_HOST}/g" /etc/shibboleth/shibboleth2.xml
sudo sed -i "s/SHIBBOLETH_SP_HOSTNAME/${SP_HOST}/g" /etc/shibboleth/shibboleth2.xml

# Retrieving IdP metadata into SP
cd /etc/shibboleth
IDP_URL="$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https://${IDP_HOST}:${IDP_TOMCAT_HTTPS_PORT}"; else echo "http://${IDP_HOST}:${IDP_TOMCAT_HTTP_PORT}"; fi)/idp/shibboleth"
echo "IDP URL is ${IDP_URL}"
sudo wget --no-check-certificate "${IDP_URL}" -O idp-metadata.xml

# Updating IDP with SP reference
# sudo sed -i '/maxRefreshDelay="P1D" \/>/s/$/\n\n        <metadata:MetadataProvider xsi:type="FilesystemMetadataProvider"\
#                                    xmlns="urn:mace:shibboleth:2.0:metadata"\
#                                    id="URLMD"\
#                                    metadataFile="'$(echo "${IDP_HOME}" | sed 's/\//\\\//g')'\/metadata\/'${SP_HOST}'.xml" \/>/' "${IDP_HOME}"/conf/relying-party.xml

sudo sed -i '/maxRefreshDelay="P1D" \/>/s/$/\n\n        <MetadataProvider xsi:type="FilesystemMetadataProvider"\
                                   xmlns="urn:mace:shibboleth:2.0:metadata"\
                                   id="URLMD"\
                                   metadataFile="'$(echo "${IDP_HOME}" | sed 's/\//\\\//g')'\/metadata\/'${SP_HOST}'.xml" \/>/' "${IDP_HOME}"/conf/relying-party.xml

# Shibboleth SP setup [END]

# Apache setup [BEGIN]
SP_URL="$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https://${SP_HOST}:${SP_TOMCAT_HTTPS_PORT}"; else echo "http://${SP_HOST}:${SP_TOMCAT_HTTP_PORT}"; fi)/nuxeo/"

# sudo bash -c "echo '<VirtualHost *:80>
#     ServerName ${IDP_HOST}
#     <Proxy ajp://localhost:8009/idp/*>
#       Allow from all
#     </Proxy>
#     ProxyPass /idp/ ajp://localhost:8009/idp/
# </VirtualHost>' > /etc/apache2/sites-available/${IDP_HOST}.conf"

# sudo bash -c "echo '<VirtualHost *:80>
#     ServerName ${SP_HOST}
#
#     ProxyPass /nuxeo/ ${SP_URL}
#     ProxyPassReverse /nuxeo/ ${SP_URL}
#     ProxyPreserveHost On
#
#     <Location /Shibboleth.sso>
#         SetHandler shib
#     </Location>
#
#     <Location /nuxeo>
#         AuthType shibboleth
# 		    ShibRequireSession On
# 		    require valid-user
# 		    ShibUseHeaders On
#     </Location>
# </VirtualHost>' > /etc/apache2/sites-available/${SP_HOST}.conf"

# openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/sp.yourdomain.com.key -out /etc/ssl/certs/sp.yourdomain.com.crt

sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/${SP_HOST}.key -out /etc/ssl/certs/${SP_HOST}.crt -subj "/CN=${SP_HOST}"

sudo bash -c "echo '<VirtualHost *:80>
    ServerName ${SP_HOST}

    ProxyPass /nuxeo/ ${SP_URL}
    ProxyPassReverse /nuxeo/ ${SP_URL}
    ProxyPreserveHost On

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/${SP_HOST}.crt
    SSLCertificateKeyFile /etc/ssl/private/${SP_HOST}.key

    <Location /Shibboleth.sso>
        SetHandler shib
    </Location>

    <Location /nuxeo>
        AuthType shibboleth
		    ShibRequireSession On
		    require valid-user
		    ShibUseHeaders On
    </Location>
</VirtualHost>' > /etc/apache2/sites-available/${SP_HOST}.conf"

sudo a2ensite ${SP_HOST}
sudo a2enmod ssl proxy_http proxy_ajp proxy_connect

sudo service shibd restart
sudo service apache2 restart
# Apache setup [END]

# Retrieving SP metadata into IdP location (SP has to be up)
# cd "${IDP_HOME}"/metadata/
# sudo wget --no-check-certificate $(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)://${SP_HOST}/Shibboleth.sso/Metadata -O ${SP_HOST}.xml

# need to restart the Idp and SP

# sudo docker run -d --name ${NUXEO_CONTAINER} -e "NUXEO_CLID=${NUXEO_CLID}" -e "NUXEO_INSTALL_HOTFIX=true" -e "NUXEO_PACKAGES=shibboleth-authentication" -p ${SP_TOMCAT_HTTP_PORT}:8080 nuxeo:${NUXEO_VERSION}

# sudo docker run -d --name ${NUXEO_CONTAINER} -e "NUXEO_CLID=${NUXEO_CLID}" -e "NUXEO_INSTALL_HOTFIX=true" -e "NUXEO_PACKAGES=shibboleth-authentication ffischer-710-0.0.0-SNAPSHOT" -p ${SP_TOMCAT_HTTP_PORT}:8080 nuxeo:${NUXEO_VERSION}

# here we need to check nuxeo is started then stop it and inject the contribution into the container filesystem
# then restart the container

# sudo docker stop ${NUXEO_CONTAINER}
# sudo systemctl stop apache2
# sudo systemctl stop shibd
# sudo -H -u tomcat bash -c "cd ${IDP_TOMCAT_HOME}/bin;./shutdown.sh"
# HERE INJECT the contribution into Nuxeo
# sudo -H -u tomcat bash -c "cd ${IDP_TOMCAT_HOME}/bin;./startup.sh"
# wait for complete startup
# sudo systemctl start shibd
# wait for complete startup
# sudo systemctl start apache2
# wait for complete startup
# sudo docker start ${NUXEO_CONTAINER}
# wait for complete startup


# sudo apt-get update
# sudo apt-get install -y --no-install-recommends \
#     perl \
#     locales \
#     pwgen \
#     imagemagick \
#     ffmpeg2theora \
#     ufraw \
#     poppler-utils \
#     libreoffice \
#     libwpd-tools \
#     exiftool \
#     ghostscript
#
# sudo apt-get install unzip -y
#
# cd /tmp
# wget http://community.nuxeo.com/static/releases/nuxeo-7.10/nuxeo-cap-7.10-tomcat.zip
# cd /opt
# sudo unzip /tmp/nuxeo-cap-7.10-tomcat.zip
#
# cd nuxeo-cap-7.10-tomcat/nxserver/data
# sudo bash -c "echo \"${NUXEO_CLID/--/\\n}\" > instance.clid"
# sudo ./nuxeoctl mp-hotfix --relax=false --accept=true
# sudo ./nuxeoctl mp-install shibboleth-authentication --relax=false --accept=true

# ServerName sp.shibboleth.com
#
# <Proxy ajp://localhost:8009/nuxeo/*>
#   Allow from all
# </Proxy>
#
# ProxyRequests On
# ProxyPass /nuxeo/ ajp://localhost:8009/nuxeo/
# ProxyPassReverse /nuxeo/ ajp://localhost:8009/nuxeo/
