#!/bin/bash

# Upgrades Nuxeo Tomcat to 7.0.76

TOMCAT_SOURCE="7.0.64"
TOMCAT_TARGET="7.0.76"
WORK_FOLDER=/tmp
NUXEO_HOME=/Users/ffischer/Downloads/tomcat/nuxeo-cap-7.10-tomcat
DOWNLOAD_FOLDER=${WORK_FOLDER}/nuxeo_downloads

echo "Retrieving files..."
rm -rf ${DOWNLOAD_FOLDER}
mkdir -p ${DOWNLOAD_FOLDER}
cd ${DOWNLOAD_FOLDER}
wget http://www-eu.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz
wget https://www.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
wget https://www.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.md5
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.sha1
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.md5
wget https://archive.apache.org/dist/tomcat/tomcat-7/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.sha1

echo "Checking archives..."
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.md5; echo >> tomcat-juli-adapters.jar.md5
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.sha1; echo >> tomcat-juli-adapters.jar.sha1
sed -i 's/\*/ /g' tomcat-juli.jar.md5; echo >> tomcat-juli.jar.md5
sed -i 's/\*/ /g' tomcat-juli.jar.sha1; echo >> tomcat-juli.jar.sha1
md5sum -c apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
shasum -c apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
md5sum -c tomcat-juli-adapters.jar.md5
shasum -c tomcat-juli-adapters.jar.sha1
md5sum -c tomcat-juli.jar.md5
shasum -c tomcat-juli.jar.sha1

echo "Paching Nuxeo..."
# upgrading files from core distribution
tar zxf apache-tomcat-${TOMCAT_TARGET}.tar.gz
cp apache-tomcat-${TOMCAT_TARGET}/lib/* ${NUXEO_HOME}/lib
cp apache-tomcat-${TOMCAT_TARGET}/bin/*.jar ${NUXEO_HOME}/bin
cp apache-tomcat-${TOMCAT_TARGET}/bin/catalina-tasks.xml ${NUXEO_HOME}/bin
cp apache-tomcat-${TOMCAT_TARGET}/lib/tomcat-jdbc.jar ${NUXEO_HOME}/nxserver/lib/tomcat-jdbc-${TOMCAT_TARGET}.jar
rm ${NUXEO_HOME}/nxserver/lib/tomcat-jdbc-${TOMCAT_SOURCE}.jar
cp apache-tomcat-${TOMCAT_TARGET}/bin/tomcat-juli.jar ${NUXEO_HOME}/nxserver/lib/tomcat-juli-${TOMCAT_TARGET}.jar
rm ${NUXEO_HOME}/nxserver/lib/tomcat-juli-${TOMCAT_SOURCE}.jar
# upgrading files from extras
cp tomcat-juli.jar ${NUXEO_HOME}/bin
cp tomcat-juli-adapters.jar ${NUXEO_HOME}/lib
cp apache-tomcat-${TOMCAT_TARGET}/RELEASE-NOTES ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/LICENSE ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/NOTICE ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/RUNNING.txt ${NUXEO_HOME}/doc-tomcat
sed 's/7\.0\.64/'${TOMCAT_TARGET}'/g' ${NUXEO_HOME}/templates/nuxeo.defaults
