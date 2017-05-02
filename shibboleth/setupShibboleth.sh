#!/bin/bash

# Setting up a Shibboleth 2 server based on Funsho's notes, various articles, lots of forums, and numerous issues
# see NXBT-946

# TODO finish this script
# TODO make heap Xmx a variable (512m for example?)
# TODO clean installation folders (see /tmp)
# TODO make apache ports for SP a parameter
# TODO cleanup folder

ORIGIN_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"
TOMCAT_VERSION="8.0.43"

SHIB_LDAP_USERS_BASE_DN="dc=nuxeo,dc=com"
SHIB_LDAP_ADMIN_BIND_DN="cn=admin,${SHIB_LDAP_USERS_BASE_DN}"
SHIB_LDAP_ADMIN_BIND_PASSWORD="password"

IDP_HOST="idp.shibboleth.com"
IDP_HOME="/opt/shibboleth-idp"
IDP_STORE_PASS="/opt/shibboleth-idp"
IDP_TOMCAT_FOLDER="tomcat-shib-idp"
IDP_TOMCAT_HOME="/opt/${IDP_TOMCAT_FOLDER}"
IDP_TOMCAT_HTTP_PORT="7080"
IDP_TOMCAT_HTTPS_PORT="7443"
IDP_TOMCAT_AJP_PORT="7009"
IDP_TOMCAT_SHUTDOWN_PORT="7005"
IDP_SSL_ENABLED="yes"
IDP_FRONT_HTTP_PORT="${IDP_TOMCAT_HTTP_PORT}"
IDP_FRONT_HTTPS_PORT="${IDP_TOMCAT_HTTPS_PORT}"

# LDAP_HOST="ldap.shibboleth.com"
LDAP_HOST="${IDP_HOST}"
LDAP_CONTAINER="shibboleth_ldap"
LDAP_SSL_ENABLED="no"

SP_HOST="sp.shibboleth.com"
SP_SSL_ENABLED="yes"
SP_TOMCAT_HTTP_PORT="9090"
SP_TOMCAT_HTTPS_PORT="9443"

NUXEO_SSL_ENABLED="no"
NUXEO_CONTAINER="shibboleth_nuxeo"
NUXEO_VERSION="7.10"
NUXEO_CLID="22adb138-fa4b-4f10-abb2-46f6ca816056--0894cf15-c745-45fe-b4fd-52422c0e9606"
NUXEO_INSTALL_HOTFIX="yes"

main() {
  if [ "$1" = "idp" ]; then
    checkReachableHosts || exit 1
    checkDocker || exit 1
    setupIDP
  elif [ "$1" = "sp" ]; then
    checkReachableHosts || exit 1
    setupSP
  elif [ "$1" = "regsp" ]; then
    checkReachableHosts || exit 1
    registerSPinIDP
  elif [ "$1" = "nuxeo" ]; then
    checkDocker || exit 1
    setupNuxeo
  elif [ "$1" = "all" ]; then
    checkReachableHosts || exit 1
    checkDocker || exit 1
    setupIDP
    setupSP
    registerSPinIDP
    nuxeo
  else
    echo "ERROR: unknown option"
    echo
    usage
    exit 1
  fi
}

setupIDP() {
  echo "Retrieving LDAP docker image and starting it up..."
  sudo docker run --env LDAP_ORGANISATION="Nuxeo" --env LDAP_DOMAIN="nuxeo.com" \
  --env LDAP_ADMIN_PASSWORD="${SHIB_LDAP_ADMIN_BIND_PASSWORD}" --env LDAP_BASE_DN="${SHIB_LDAP_USERS_BASE_DN}" \
  --env LDAP_CONFIG_PASSWORD="${SHIB_LDAP_ADMIN_BIND_PASSWORD}" --name ${LDAP_CONTAINER} -p 0.0.0.0:389:389 --detach osixia/openldap:1.1.8

  echo "Waiting for LDAP server to be up to create a nuxeo user..."
  until sudo docker exec -i ${LDAP_CONTAINER} ldapwhoami -x -H ldap://localhost -D "${SHIB_LDAP_ADMIN_BIND_DN}" -w ${SHIB_LDAP_ADMIN_BIND_PASSWORD} 2>/dev/null; do
    echo "OpenLDAP is unavailable - sleeping"
    sleep 1
  done

  echo
  echo "Creating test user and Administrator..."
  echo "dn: uid=nuxeotest,${SHIB_LDAP_USERS_BASE_DN}
objectClass: inetOrgPerson
cn: nuxeotest
uid: nuxeotest
userPassword: password
mail: nuxeotest@nuxeo.com
sn: nuxeotest
" | sudo docker exec -i ${LDAP_CONTAINER} ldapadd -x -H ldap://localhost -D "${SHIB_LDAP_ADMIN_BIND_DN}" -w ${SHIB_LDAP_ADMIN_BIND_PASSWORD}

  echo "dn: uid=Administrator,${SHIB_LDAP_USERS_BASE_DN}
objectClass: inetOrgPerson
cn: Administrator
uid: Administrator
userPassword: Administrator
mail: Administrator@nuxeo.com
sn: Administrator
" | sudo docker exec -i ${LDAP_CONTAINER} ldapadd -x -H ldap://localhost -D "${SHIB_LDAP_ADMIN_BIND_DN}" -w ${SHIB_LDAP_ADMIN_BIND_PASSWORD}

  echo "Installing JDK 8..."
  sudo apt-get install openjdk-8-jdk -y -qq > /dev/null
  export JAVA_HOME=$(sudo update-java-alternatives -l | sed 's/^[^\/]*\(\/.*\)$/\1/')
  echo "JAVA_HOME is $JAVA_HOME"

  echo
  echo "Retrieving and installing Tomcat..."
  cd /tmp \
  && wget http://www-us.apache.org/dist/tomcat/tomcat-8/v"${TOMCAT_VERSION}"/bin/apache-tomcat-"${TOMCAT_VERSION}".tar.gz \
  && sudo mkdir -p "${IDP_TOMCAT_HOME}" \
  && sudo tar xzf apache-tomcat-"${TOMCAT_VERSION}".tar.gz -C "${IDP_TOMCAT_HOME}" --strip-components=1

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

  echo "Tomcat manager application can be accessed with tomcat/password."

  echo
  echo "Retrieving IDP archive..."
  cd /tmp \
  && wget http://shibboleth.net/downloads/identity-provider/2.4.5/shibboleth-identityprovider-2.4.5-bin.tar.gz \
  && tar zxf shibboleth-identityprovider-2.4.5-bin.tar.gz \
  && cd shibboleth-identityprovider-2.4.5

  echo
  echo "Patching IDP installation files..."
  patch -p0 < "${ORIGIN_FOLDER}/build.xml.patch"
  sed -i "s/SHIBBOLETH_IDP_HOME/${IDP_HOME//\//\\/}/" src/installer/resources/build.xml
  sed -i "s/SHIBBOLETH_IDP_HOSTNAME/${IDP_HOST}/" src/installer/resources/build.xml
  sed -i "s/SHIBBOLETH_IDP_PORT/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "${IDP_FRONT_HTTPS_PORT}"; else echo "${IDP_FRONT_HTTP_PORT}"; fi)/" src/installer/resources/build.xml
  sed -i "s/SHIBBOLETH_IDP_KEYSTORE_PASSWORD/${IDP_STORE_PASS//\//\\/}/" src/installer/resources/build.xml
  sed -i "s/SHIBBOLETH_IDP_PROTOCOL/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/" src/installer/resources/build.xml

  # by default the metadata template (used for sending assertions and responses) is using https and 8443 and some links are missing the port
  if [ ! "${IDP_SSL_ENABLED}" = "yes" ]; then
    sed -i 's/https/http/g' src/installer/resources/metadata-tmpl/idp-metadata.xml
    sed -i "s/8443/${IDP_FRONT_HTTP_PORT}/g" src/installer/resources/metadata-tmpl/idp-metadata.xml
    sed -i 's/\/$IDP_HOSTNAME$\//\/$IDP_HOSTNAME$:'${IDP_FRONT_HTTP_PORT}'\//g' src/installer/resources/metadata-tmpl/idp-metadata.xml
  else
    sed -i "s/8443/${IDP_FRONT_HTTPS_PORT}/g" src/installer/resources/metadata-tmpl/idp-metadata.xml
    sed -i 's/\/$IDP_HOSTNAME$\//\/$IDP_HOSTNAME$:'${IDP_FRONT_HTTPS_PORT}'\//g' src/installer/resources/metadata-tmpl/idp-metadata.xml
  fi

  echo
  echo "Installing IDP..."
  sudo bash -c "export JAVA_HOME=${JAVA_HOME}; ./install.sh"

  echo
  echo "Setting logs to DEBUG level..."
  sudo sed -i 's/<logger name="edu.internet2.middleware.shibboleth"\s*level=".*"\/>/<logger name="edu.internet2.middleware.shibboleth" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml
  sudo sed -i 's/<logger name="org.opensaml"\s*level=".*"\/>/<logger name="org.opensaml" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml
  sudo sed -i 's/<logger name="edu.vt.middleware.ldap"\s*level=".*"\/>/<logger name="edu.vt.middleware.ldap" level="ALL"\/>/' "${IDP_HOME}"/conf/logging.xml

  echo
  echo "Setting Tomcat ports..."
  sudo sed -i '/<Connector port="8080"/s/^/<Connector protocol="org.apache.coyote.http11.Http11NioProtocol" port="8443"\n    maxThreads="200" scheme="https" secure="true" SSLEnabled="true" keystoreFile="'${IDP_HOME//\//\\/}'\/credentials\/idp.jks"\n    keystorePass="'${IDP_STORE_PASS//\//\\/}'" clientAuth="false" sslProtocol="TLS" \/>\n\n/' "${IDP_TOMCAT_HOME}"/conf/server.xml
  sudo sed -i 's/8005/'${IDP_TOMCAT_SHUTDOWN_PORT}'/g' "${IDP_TOMCAT_HOME}"/conf/server.xml
  sudo sed -i 's/8009/'${IDP_TOMCAT_AJP_PORT}'/g' "${IDP_TOMCAT_HOME}"/conf/server.xml
  sudo sed -i 's/8080/'${IDP_TOMCAT_HTTP_PORT}'/g' "${IDP_TOMCAT_HOME}"/conf/server.xml
  sudo sed -i 's/8443/'${IDP_TOMCAT_HTTPS_PORT}'/g' "${IDP_TOMCAT_HOME}"/conf/server.xml

  echo
  echo "Adding IDP to tomcat applications..."
  sudo mkdir -p "${IDP_TOMCAT_HOME}"/conf/Catalina/localhost
  sudo bash -c "echo '<Context docBase=\"${IDP_HOME}/war/idp.war\"
    privileged=\"true\"
    antiResourceLocking=\"false\"
    antiJARLocking=\"false\"
    unpackWAR=\"false\"
    swallowOutput=\"true\" />' > \"${IDP_TOMCAT_HOME}\"/conf/Catalina/localhost/idp.xml"

  echo
  echo "Post installation steps..."

  # Setting authentication method
  cd ${IDP_HOME}
  sudo patch -p0 < "${ORIGIN_FOLDER}/idphandler.patch"
  sudo sed -i "s/SHIBBOLETH_IDP_HOME/$(echo "${IDP_HOME}" | sed 's/\//\\\//g')/" conf/handler.xml

  # Setting LDAP connection details
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

  # Addding uid and mail to the attributes, set up LDAP configuration
  sudo bash -c "cat ${ORIGIN_FOLDER}/idpattribute-resolver.xml \
  | sed \"s/LDAP_HOST/${LDAP_HOST}/g;s/SHIB_LDAP_USERS_BASE_DN/${SHIB_LDAP_USERS_BASE_DN}/g;s/SHIB_LDAP_ADMIN_BIND_DN/${SHIB_LDAP_ADMIN_BIND_DN}/;s/SHIB_LDAP_ADMIN_BIND_PASSWORD/${SHIB_LDAP_ADMIN_BIND_PASSWORD}/\" \
  > \"${IDP_HOME}\"/conf/attribute-resolver.xml"

  # Addding uid and mail to the responses else they are not available
  cd "${IDP_HOME}"/conf
  sudo patch < "${ORIGIN_FOLDER}/attribute-filter.xml.patch"

  # Setting up user, group and rights
  sudo groupadd -f ${TOMCAT_GROUP}
  id -u ${TOMCAT_USER} &>/dev/null || sudo useradd -s /bin/false -g ${TOMCAT_GROUP} -d "${IDP_TOMCAT_HOME}" ${TOMCAT_USER}
  sudo chown ${TOMCAT_USER}:${TOMCAT_GROUP} ${IDP_HOME} -R
  sudo chown ${TOMCAT_USER}:${TOMCAT_GROUP} ${IDP_TOMCAT_HOME} -R

  echo
  echo "Starting IDP..."
  sudo -H -u ${TOMCAT_USER} bash -c "cd ${IDP_TOMCAT_HOME}/bin;./startup.sh"
}

setupSP() {
  echo "Retrieving and installing binaries for Apache and Shibboleth SP..."
  sudo apt-get install apache2 -y -qq > /dev/null
  sudo apt-get install libapache2-mod-shib2 -y -qq > /dev/null
  sudo curl -k -O http://pkg.switch.ch/switchaai/SWITCHaai-swdistrib.asc > /dev/null
  sudo apt-key add SWITCHaai-swdistrib.asc > /dev/null
  echo 'deb http://pkg.switch.ch/switchaai/ubuntu xenial main' | sudo tee /etc/apt/sources.list.d/SWITCHaai-swdistrib.list > /dev/null
  sudo apt-get update -y -qq > /dev/null
  sudo apt-get install shibboleth -y -qq > /dev/null

  echo
  echo "Generating key for Shibboleth..."
  sudo shib-keygen > /dev/null

  echo
  echo "Setting hosts in shibboleth2.xml..."
  cd /
  sudo patch -p0 < "${ORIGIN_FOLDER}/shibboleth2.xml.patch"
  sudo sed -i "s/SHIBBOLETH_IDP_PROTOCOL/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
  sudo sed -i "s/SHIBBOLETH_SP_PROTOCOL/$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)/g" /etc/shibboleth/shibboleth2.xml
  sudo sed -i "s/SHIBBOLETH_IDP_HOSTNAME/${IDP_HOST}/g" /etc/shibboleth/shibboleth2.xml
  sudo sed -i "s/SHIBBOLETH_IDP_PORT/$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "${IDP_FRONT_HTTPS_PORT}"; else echo "${IDP_FRONT_HTTP_PORT}"; fi)/" /etc/shibboleth/shibboleth2.xml
  sudo sed -i "s/SHIBBOLETH_SP_HOSTNAME/${SP_HOST}/g" /etc/shibboleth/shibboleth2.xml

  echo
  echo "Setting attribute mapping for uid and mail..."
  sudo sed -i '/<\/Attributes>/s/^/    <Attribute name="urn:oid:0.9.2342.19200300.100.1.1" id="uid"\/>\n    <Attribute name="urn:oid:0.9.2342.19200300.100.1.3" id="mail"\/>\n/' /etc/shibboleth/attribute-map.xml

  echo
  echo "Retrieving IdP metadata into SP..."
  cd /etc/shibboleth
  IDP_URL="$(if [ "${IDP_SSL_ENABLED}" = "yes" ]; then echo "https://${IDP_HOST}:${IDP_TOMCAT_HTTPS_PORT}"; else echo "http://${IDP_HOST}:${IDP_TOMCAT_HTTP_PORT}"; fi)/idp/shibboleth"
  echo "IDP URL is ${IDP_URL}"
  sudo wget --no-check-certificate "${IDP_URL}" -O idp-metadata.xml

  echo
  echo "Generating SP keys..."
  sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/${SP_HOST}.key -out /etc/ssl/certs/${SP_HOST}.crt -subj "/CN=${SP_HOST}"

  echo
  echo "Configuring front Apache on port 443..."
  SP_URL="$(if [ "${NUXEO_SSL_ENABLED}" = "yes" ]; then echo "https://${SP_HOST}:${SP_TOMCAT_HTTPS_PORT}"; else echo "http://${SP_HOST}:${SP_TOMCAT_HTTP_PORT}"; fi)/nuxeo/"

  sudo bash -c "echo '<VirtualHost *:443>
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
  sudo a2enmod ssl proxy_http

  echo
  echo "Starting Shibboleth and Apache servers (as root)..."
  sudo service shibd restart
  sudo service apache2 restart
}

registerSPinIDP() {
  echo "Stopping IDP..."
  sudo -H -u ${TOMCAT_USER} bash -c "cd ${IDP_TOMCAT_HOME}/bin;./shutdown.sh"

  echo
  echo "Updating IDP with SP reference..."
  sudo sed -i '/maxRefreshDelay="P1D" \/>/s/$/\n\n        <MetadataProvider xsi:type="FilesystemMetadataProvider"\
                                     xmlns="urn:mace:shibboleth:2.0:metadata"\
                                     id="URLMD"\
                                     metadataFile="'$(echo "${IDP_HOME}" | sed 's/\//\\\//g')'\/metadata\/'${SP_HOST}'.xml" \/>/' "${IDP_HOME}"/conf/relying-party.xml

  echo
  echo "Retrieving SP metadata into IdP location (SP has to be up)..."
  cd "${IDP_HOME}"/metadata/
  SP_URL="$(if [ "${SP_SSL_ENABLED}" = "yes" ]; then echo "https"; else echo "http"; fi)://${SP_HOST}/Shibboleth.sso/Metadata"
  echo "SP_URL URL is ${SP_URL}"
  sudo wget --no-check-certificate ${SP_URL} -O ${SP_HOST}.xml
  sudo chown ${TOMCAT_USER}:${TOMCAT_GROUP} ${SP_HOST}.xml

  echo
  echo "Starting IDP..."
  sudo -H -u ${TOMCAT_USER} bash -c "cd ${IDP_TOMCAT_HOME}/bin;./startup.sh"
}

setupNuxeo() {
  echo "Nuxeo setup..."
  # build a package here for the shibboleth contribution

  # sudo docker run -d --name ${NUXEO_CONTAINER} -e "NUXEO_CLID=${NUXEO_CLID}" -e "NUXEO_INSTALL_HOTFIX=true" -e "NUXEO_PACKAGES=shibboleth-authentication ffischer-710-0.0.0-SNAPSHOT" -p ${SP_TOMCAT_HTTP_PORT}:8080 nuxeo:${NUXEO_VERSION}
}

usage() {
  echo "the usage..."
}

checkReachableHosts() {
  echo -n "Checking hosts are reachable (LDAP, IDP, SP)..."
  if ! ping -w 2 "${LDAP_HOST}" > /dev/null || ! ping -w 2 "${IDP_HOST}" > /dev/null || ! ping -w 2 "${SP_HOST}" > /dev/null; then
    echo -e "KO\n"
    echo "ERROR: hosts unreachable, please check the following hosts are reachable:"
    echo -e "\t${LDAP_HOST} (LDAP) ${IDP_HOST} (IDP) ${SP_HOST} (SP)"
    echo
    echo "Hosts can be added to a DNS or to your local /etc/hosts file."
    echo "If all Shibboleth components are on the same machine, on can add the following to the /etc/hosts file:"
    echo "127.0.0.1	localhost ${LDAP_HOST} ${IDP_HOST} ${SP_HOST}"
    return 1
  else
    echo -e "OK\n"
  fi
}

checkDocker() {
  echo -n "Checking Docker is installed..."
  # install docker if not installed
  if ! docker 2>1 > /dev/null; then
    echo -e "KO\n"
    echo "Installing Docker..."
    sudo apt-get update -y > /dev/null
    sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D  > /dev/null
    sudo apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main' > /dev/null
    sudo apt-get update -y -qq > /dev/null
    sudo apt-get install -y docker-engine > /dev/null
    sudo systemctl status docker
    if sudo systemctl status docker | grep dead; then
      echo "ERROR: docker was not installed!"
      return 1
    fi
  else
    echo -e "OK\n"
  fi
}

main "$@"
