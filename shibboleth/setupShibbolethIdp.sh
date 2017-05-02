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

# A FAIRE => propager les attributs uid et email en ajoutant dans attribute-filter.xml uid et email (voir la config de transient)
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
IDP_STORE_PASS="idpstorepass"
IDP_TOMCAT_FOLDER="tomcat-shib-idp"
IDP_TOMCAT_HOME="/opt/${IDP_TOMCAT_FOLDER}"
IDP_TOMCAT_HTTP_PORT="8080"
IDP_TOMCAT_HTTPS_PORT="8443"
IDP_TOMCAT_SHUTDOWN_PORT="8006"
IDP_SSL_ENABLED="yes"
IDP_FRONT_HTTP_PORT="80"
IDP_FRONT_HTTPS_PORT="443"

# LDAP_HOST="ldap.shibboleth.com"
LDAP_HOST="${IDP_HOST}"
LDAP_CONTAINER="shibboleth_ldap"
LDAP_SSL_ENABLED="no"

SP_HOST="sp.shibboleth.com"
SP_SSL_ENABLED="yes"
SP_TOMCAT_HTTP_PORT="8180"
NUXEO_CONTAINER="shibboleth_nuxeo"
NUXEO_VERSION="7.10"
NUXEO_CLID="22adb138-fa4b-4f10-abb2-46f6ca816056--0894cf15-c745-45fe-b4fd-52422c0e9606"
NUXEO_INSTALL_HOTFIX="yes"

# maybe it is needed to detect the IP and map the hostnames to this IP instead of loopback

# Adding hosts
# grep -q -E "127.0.0.1\s*${SP_HOST}" /etc/hosts || sudo bash -c "echo '127.0.0.1 ${SP_HOST}' >> /etc/hosts"
# grep -q -E "127.0.0.1\s*${LDAP_HOST}" /etc/hosts || sudo bash -c "echo '127.0.0.1 ${LDAP_HOST}' >> /etc/hosts"
# grep -q -E "127.0.0.1\s*${IDP_HOST}" /etc/hosts || sudo bash -c "echo '127.0.0.1 ${IDP_HOST}' >> /etc/hosts"

# if idp and sp are on different machines
# sudo apt-get install ntp -y -qq

# LDAP setup [BEGIN]
sudo docker run --env LDAP_ORGANISATION="Nuxeo" --env LDAP_DOMAIN="nuxeo.com" \
--env LDAP_ADMIN_PASSWORD="${SHIB_LDAP_ADMIN_BIND_PASSWORD}" --env LDAP_BASE_DN="${SHIB_LDAP_USERS_BASE_DN}" \
--env LDAP_CONFIG_PASSWORD="${SHIB_LDAP_ADMIN_BIND_PASSWORD}" --name ${LDAP_CONTAINER} -p 0.0.0.0:389:389 --detach osixia/openldap:1.1.8

# iptables -t nat -A DOCKER -p tcp --dport 389 -j DNAT --to-destination 10.213.3.40:389

# command to double-check the LDAP content
# docker exec shibboleth_ldap ldapsearch -x -H ldap://localhost -b ${SHIB_LDAP_USERS_BASE_DN} -D "cn=admin,${SHIB_LDAP_USERS_BASE_DN}" -w password

# Waiting for LDAP server to be up to create nuxeo user
# ldapwhoami -x -H ldap://10.213.3.40 -D "cn=admin,dc=nuxeo,dc=com" -w password
# docker exec shibboleth_ldap ldapwhoami -x -H ldap://localhost -D "cn=admin,dc=nuxeo,dc=com" -w password

until sudo docker exec -i ${LDAP_CONTAINER} ldapwhoami -x -H ldap://localhost -D "${SHIB_LDAP_ADMIN_BIND_DN}" -w ${SHIB_LDAP_ADMIN_BIND_PASSWORD} 2>/dev/null; do
  echo "OpenLDAP is unavailable - sleeping"
  sleep 1
done

sleep 1
echo "OpenLDAP is up - resuming setup"

echo "dn: uid=nuxeotest,${SHIB_LDAP_USERS_BASE_DN}
objectClass: inetOrgPerson
cn: nuxeotest
uid: nuxeotest
userPassword: password
mail: nuxeotest@nuxeo.com
sn: nuxeotest
" | sudo docker exec -i ${LDAP_CONTAINER} ldapadd -x -H ldap://localhost -D "${SHIB_LDAP_ADMIN_BIND_DN}" -w ${SHIB_LDAP_ADMIN_BIND_PASSWORD}


# ldapsearch -x -H ldap://10.213.3.40 -b "dc=nuxeo,dc=com" -D "${SHIB_LDAP_ADMIN_BIND_DN}" -wpassword

# LDAP setup [END]

# Java and Tomcat 8 setup [BEGIN]

# installing java 8
sudo apt-get install openjdk-8-jdk -y -qq
export JAVA_HOME=$(sudo update-java-alternatives -l | sed 's/^[^\/]*\(\/.*\)$/\1/')

# installing tomcat 8.0.x
cd /tmp \
&& wget http://www-us.apache.org/dist/tomcat/tomcat-8/v8.0.43/bin/apache-tomcat-8.0.43.tar.gz \
&& sudo mkdir -p "${IDP_TOMCAT_HOME}" \
&& sudo tar xzf apache-tomcat-8*tar.gz -C "${IDP_TOMCAT_HOME}" --strip-components=1

# && sudo tar xzvf apache-tomcat-8*tar.gz -C "${IDP_TOMCAT_HOME}" --strip-components=1 \
# && sudo groupadd -f ${TOMCAT_GROUP} \
# && id -u ${TOMCAT_USER} &>/dev/null || sudo useradd -s /bin/false -g ${TOMCAT_GROUP} -d "${IDP_TOMCAT_HOME}" ${TOMCAT_USER} \
# && cd "${IDP_TOMCAT_HOME}" \
# && sudo chown -R ${TOMCAT_USER}:${TOMCAT_GROUP} "${IDP_TOMCAT_HOME}"

sudo bash -c "echo '<?xml version='\''1.0'\'' encoding='\''utf-8'\''?>
<tomcat-users>
  <role rolename=\"tomcat\"/>
  <role rolename=\"admin-gui\"/>
  <role rolename=\"manager-gui\"/>
  <role rolename=\"role1\"/>
  <user username=\"tomcat\" password=\"password\" roles=\"tomcat,manager-gui,admin-gui\"/>
  <user username=\"both\" password=\"password\" roles=\"tomcat,role1\"/>
  <user username=\"role1\" password=\"password\" roles=\"role1\"/>
</tomcat-users>' > \"${IDP_TOMCAT_HOME}\"/conf/tomcat-users.xml"

# Java and Tomcat 8 setup [END]

# Shibboleth IdP setup [BEGIN]
cd /tmp \
&& wget http://shibboleth.net/downloads/identity-provider/2.4.5/shibboleth-identityprovider-2.4.5-bin.tar.gz \
&& tar zxf shibboleth-identityprovider-2.4.5-bin.tar.gz \
&& cd shibboleth-identityprovider-2.4.5

# diff -u src/installer/resources/build.xml.orig src/installer/resources/build.xml > idpparams.patch

patch -p0 < "${ORIGIN_FOLDER}/build.xml.patch"

sed -i "s/SHIBBOLETH_IDP_HOME/$(echo "${IDP_HOME}" | sed 's/\//\\\//g')/" src/installer/resources/build.xml
# sed -i "s/SHIBBOLETH_IDP_HOSTNAME/$(echo "${IDP_HOST}" | sed 's/\//\\\//g')/" src/installer/resources/build.xml
sed -i "s/SHIBBOLETH_IDP_HOSTNAME/${IDP_HOST}/" src/installer/resources/build.xml
# sed -i "s/SHIBBOLETH_IDP_KEYSTORE_PASSWORD/$(echo "${IDP_STORE_PASS}" | sed 's/\//\\\//g')/" src/installer/resources/build.xml
sed -i "s/SHIBBOLETH_IDP_KEYSTORE_PASSWORD/${IDP_STORE_PASS}/" src/installer/resources/build.xml
sed -i "s/SHIBBOLETH_IDP_PROTOCOL/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/" src/installer/resources/build.xml

# by default the metadata template (used for sending assertions and responses) is using https and 8443
if [ ! "${IDP_SSL_ENABLED}" = "yes" ]; then
  sed -i 's/https/http/g' src/installer/resources/metadata-tmpl/idp-metadata.xml
  sed -i "s/8443/${IDP_FRONT_HTTP_PORT}/g" src/installer/resources/metadata-tmpl/idp-metadata.xml
else
  sed -i "s/8443/${IDP_FRONT_HTTPS_PORT}/g" src/installer/resources/metadata-tmpl/idp-metadata.xml
fi

# idp.home
# idp.hostname
# idp.keystore.pass

sudo bash -c "export JAVA_HOME=${JAVA_HOME}; ./install.sh"

sudo sed -i 's/<logger name="edu.internet2.middleware.shibboleth"\s*level=".*"\/>/<logger name="edu.internet2.middleware.shibboleth" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml
sudo sed -i 's/<logger name="org.opensaml"\s*level=".*"\/>/<logger name="org.opensaml" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml
sudo sed -i 's/<logger name="edu.vt.middleware.ldap"\s*level=".*"\/>/<logger name="edu.vt.middleware.ldap" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml

# Updating Tomcat shutdown port
sudo sed -i 's/<Server\s*port=".*"\s*shutdown="SHUTDOWN">/<Server port="'${IDP_TOMCAT_SHUTDOWN_PORT}'" shutdown="SHUTDOWN">/' "${IDP_TOMCAT_HOME}"/conf/server.xml

# Adding IDP to tomcat applications
sudo mkdir -p "${IDP_TOMCAT_HOME}"/conf/Catalina/localhost
sudo bash -c "echo '<Context docBase=\"${IDP_HOME}/war/idp.war\"
  privileged=\"true\"
  antiResourceLocking=\"false\"
  antiJARLocking=\"false\"
  unpackWAR=\"false\"
  swallowOutput=\"true\" />' > \"${IDP_TOMCAT_HOME}\"/conf/Catalina/localhost/idp.xml"

# sed '/<dependency>/s/^/<--/;/<\/dependency>/s/$/-->/' inputfile > outputfile

cd ${IDP_HOME}

sudo patch -p0 < "${ORIGIN_FOLDER}/idphandler.patch"

sudo sed -i "s/SHIBBOLETH_IDP_HOME/$(echo "${IDP_HOME}" | sed 's/\//\\\//g')/" conf/handler.xml

# sed '0,/<ph?LoginHandler\s*xsi:type="ph?RemoteUser">/s/^\s*/<!--\n    /;0,/<\/ph:LoginHandler>/s/$/\n-->/' "${IDP_HOME}"/conf/handler.xml
# sed 's/<ph.*LoginHandler.*="ph.*RemoteUser">/<!--\n    <ph:LoginHandler xsi:type="ph:RemoteUser">/' "${IDP_HOME}"/conf/handler.xml
# sed 's/<ph.*LoginHandler\s*xsi.*type="ph.*RemoteUser">/<!--\n    <ph:LoginHandler xsi:type="ph:RemoteUser">/' "${IDP_HOME}"/conf/handler.xml

sudo bash -c "echo 'ShibUserPassAuth {
  edu.vt.middleware.ldap.jaas.LdapLoginModule required
  	ldapUrl=\"ldap://'${LDAP_HOST}'\"
  	baseDn=\"'${SHIB_LDAP_USERS_BASE_DN}'\"
  	bindDN=\"'${SHIB_LDAP_ADMIN_BIND_DN}'\"
  	bindCredential=\"'${SHIB_LDAP_ADMIN_BIND_PASSWORD}'\"
    serviceUser=\"'${SHIB_LDAP_ADMIN_BIND_DN}'\"
    serviceCredential=\"'${SHIB_LDAP_ADMIN_BIND_PASSWORD}'\"
  	ssl=\"'$(if [ "${LDAP_SSL_ENABLED}" = "yes" ]; then echo "true"; else echo "false"; fi)'\"
    tls=\"'$(if [ "${LDAP_SSL_ENABLED}" = "yes" ]; then echo "true"; else echo "false"; fi)'\"
  	userFilter=\"uid={0}\"
    subtreeSearch="true"
  ;
};' > \"${IDP_HOME}\"/conf/login.config"

sudo bash -c "cat ${ORIGIN_FOLDER}/idpattribute-resolver.xml \
| sed \"s/LDAP_HOST/${LDAP_HOST}/g;s/SHIB_LDAP_USERS_BASE_DN/${SHIB_LDAP_USERS_BASE_DN}/g;s/SHIB_LDAP_ADMIN_BIND_DN/${SHIB_LDAP_ADMIN_BIND_DN}/;s/SHIB_LDAP_ADMIN_BIND_PASSWORD/${SHIB_LDAP_ADMIN_BIND_PASSWORD}/\" \
> \"${IDP_HOME}\"/conf/attribute-resolver.xml"

sudo groupadd -f ${TOMCAT_GROUP}
id -u ${TOMCAT_USER} &>/dev/null || sudo useradd -s /bin/false -g ${TOMCAT_GROUP} -d "${IDP_TOMCAT_HOME}" ${TOMCAT_USER}
sudo chown ${TOMCAT_USER}:${TOMCAT_GROUP} ${IDP_HOME} -R
sudo chown ${TOMCAT_USER}:${TOMCAT_GROUP} ${IDP_TOMCAT_HOME} -R

sudo -H -u tomcat bash -c "cd ${IDP_TOMCAT_HOME}/bin;./startup.sh"

sudo apt-get install apache2 -y -qq

# no need to generate a certificate, we use the IDP generated one
# sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/${IDP_HOST}.key -out /etc/ssl/certs/${IDP_HOST}.crt -subj "/CN=${IDP_HOST}"

# sudo bash -c "echo '<VirtualHost *:80>
#     ServerName ${IDP_HOST}
#     <Proxy ajp://localhost:8009/idp/*>
#       Allow from all
#     </Proxy>
#     ProxyPass /idp/ ajp://localhost:8009/idp/
# </VirtualHost>' > /etc/apache2/sites-available/${IDP_HOST}.conf"

# sudo bash -c "echo '<VirtualHost *:443>
#   ServerName ${IDP_HOST}
#   SSLEngine on
#   SSLCertificateFile /etc/ssl/certs/${IDP_HOST}.crt
#   SSLCertificateKeyFile /etc/ssl/private/${IDP_HOST}.key
#   # If you have an intermediate certificate from an SSL provider, you can specify it here
#   # SSLCertificateChainFile /etc/ssl/certs/your-ssl-authority-intermediate.crt
#   <Proxy ajp://localhost:8009/idp/*>
#     Allow from all
#   </Proxy>
#   ProxyPass /idp/ ajp://localhost:8009/idp/
# </VirtualHost>' > /etc/apache2/sites-available/${IDP_HOST}.conf"

sudo bash -c "echo '<VirtualHost *:443>
  ServerName ${IDP_HOST}
  SSLEngine on
  SSLCertificateFile ${IDP_HOME}/credentials/idp.crt
  SSLCertificateKeyFile ${IDP_HOME}/credentials/idp.key
  # If you have an intermediate certificate from an SSL provider, you can specify it here
  # SSLCertificateChainFile /etc/ssl/certs/your-ssl-authority-intermediate.crt
  <Proxy ajp://localhost:8009/idp/*>
    Allow from all
  </Proxy>
  ProxyPass /idp/ ajp://localhost:8009/idp/
</VirtualHost>' > /etc/apache2/sites-available/${IDP_HOST}.conf"

sudo a2ensite ${IDP_HOST}
sudo a2enmod ssl proxy_ajp
sudo service apache2 restart

# Shibboleth IdP setup [END]

# URL for testing IdP is up
# http://${IDP_HOST}:${IDP_TOMCAT_HTTP_PORT}/idp/Authn/UserPassword
# http://10.213.3.40:8080/idp/Authn/UserPassword

# # Shibboleth SP setup [BEGIN]
# sudo apt-get install apache2 -y
# sudo curl -k -O http://pkg.switch.ch/switchaai/SWITCHaai-swdistrib.asc
# sudo apt-key add SWITCHaai-swdistrib.asc
# echo 'deb http://pkg.switch.ch/switchaai/ubuntu xenial main' | sudo tee /etc/apt/sources.list.d/SWITCHaai-swdistrib.list > /dev/null
# sudo apt-get update -y
# sudo apt-get install shibboleth -y
# sudo shib-keygen
#
# cd /
# sudo patch -p0 < "${ORIGIN_FOLDER}/shibboleth2.xml.patch"
# sudo sed -i "s/SHIBBOLETH_IDP_PROTOCOL/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
# sudo sed -i "s/SHIBBOLETH_SP_PROTOCOL/$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
# sudo sed -i "s/SHIBBOLETH_IDP_HOSTNAME/${IDP_HOST}/g" /etc/shibboleth/shibboleth2.xml
# sudo sed -i "s/SHIBBOLETH_SP_HOSTNAME/${SP_HOST}/g" /etc/shibboleth/shibboleth2.xml
#
# # Retrieving IdP metadata into SP
# cd /etc/shibboleth
# IDP_URL="$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https://${IDP_HOST}:${IDP_TOMCAT_HTTPS_PORT}"; else echo "http://${IDP_HOST}:${IDP_TOMCAT_HTTP_PORT}"; fi)/idp/shibboleth"
# echo "IDP URL is ${IDP_URL}"
# sudo wget --no-check-certificate "${IDP_URL}" -O idp-metadata.xml
#
# # Updating IDP with SP reference
# sudo sed -i '/maxRefreshDelay="P1D" \/>/s/$/\n\n        <metadata:MetadataProvider xsi:type="FilesystemMetadataProvider"\
#                                    xmlns="urn:mace:shibboleth:2.0:metadata"\
#                                    id="URLMD"\
#                                    metadataFile="'$(echo "${IDP_HOME}" | sed 's/\//\\\//g')'\/metadata\/'${SP_HOST}'.xml" \/>/' "${IDP_HOME}"/conf/relying-party.xml
#
# # Shibboleth SP setup [END]
#
# # Apache setup [BEGIN]
# SP_URL="$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https://${SP_HOST}:${SP_TOMCAT_HTTPS_PORT}"; else echo "http://${SP_HOST}:${SP_TOMCAT_HTTP_PORT}"; fi)/nuxeo/"
#
# sudo bash -c "echo '<VirtualHost *:80>
#     ServerName ${IDP_HOST}
#     <Proxy ajp://localhost:8009/idp/*>
#       Allow from all
#     </Proxy>
#     ProxyPass /idp/ ajp://localhost:8009/idp/
# </VirtualHost>' > /etc/apache2/sites-available/${IDP_HOST}.conf"
#
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
# sudo a2enmod proxy_ajp
# sudo a2ensite ${IDP_HOST}
# sudo a2ensite ${SP_HOST}
# sudo service apache2 restart
# # Apache setup [END]
#
# # Retrieving SP metadata into IdP location (SP has to be up)
# cd "${IDP_HOME}"/metadata/
# SP_URL="$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)://${SP_HOST}/Shibboleth.sso/Metadata"
# echo "SP_URL URL is ${SP_URL}"
# sudo wget --no-check-certificate ${SP_URL} -O ${SP_HOST}.xml
# sudo wget --no-check-certificate $(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)://${SP_HOST}/Shibboleth.sso/Metadata -O ${SP_HOST}.xml
#
# # need to restart the Idp and SP
#
# # sudo docker run -d --name ${NUXEO_CONTAINER} -e "NUXEO_CLID=${NUXEO_CLID}" -e "NUXEO_INSTALL_HOTFIX=true" -e "NUXEO_PACKAGES=shibboleth-authentication" -p ${SP_TOMCAT_HTTP_PORT}:8080 nuxeo:${NUXEO_VERSION}
#
# # here we need to check nuxeo is started then stop it and inject the contribution into the container filesystem
# # then restart the container
#
# # sudo docker stop ${NUXEO_CONTAINER}
# # sudo systemctl stop apache2
# # sudo systemctl stop shibd
# # sudo -H -u tomcat bash -c "cd ${IDP_TOMCAT_HOME}/bin;./shutdown.sh"
# # HERE INJECT the contribution into Nuxeo
# # sudo -H -u tomcat bash -c "cd ${IDP_TOMCAT_HOME}/bin;./startup.sh"
# # wait for complete startup
# # sudo systemctl start shibd
# # wait for complete startup
# # sudo systemctl start apache2
# # wait for complete startup
# # sudo docker start ${NUXEO_CONTAINER}
# # wait for complete startup
#
#
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
