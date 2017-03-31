#!/bin/bash

# Upgrades Nuxeo Tomcat to latest version

# TODOs
# make the NUXEO_HOME a parameter
# make TOMCAT_TARGET an optional parameter
# ideally, detect the current Tomcat version from the NUXEO_HOME deployed (jar command and nuxeo.default to compare)

TOMCAT_ARCHIVE_URL="https://archive.apache.org/dist/tomcat/tomcat-7"
TOMCAT_LATEST_URL="http://www.apache.org/dist/tomcat/tomcat-7"
TOMCAT_SOURCE="7.0.64"

# autodetects latest version
TOMCAT_TARGET=$(curl -sSL ${TOMCAT_LATEST_URL} | grep href=\"v | sed 's/.*href="v\(7.0.[0-9]*\).*/\1/g')
TOMCAT_TARGET=${TOMCAT_TARGET:-7.0.75} # fallback to 7.0.75 if autodetection failed
WORK_FOLDER=/tmp
NUXEO_HOME=/Users/ffischer/Downloads/tomcat/nuxeo-cap-7.10-tomcat
DOWNLOAD_FOLDER=${WORK_FOLDER}/nuxeo_downloads

echo -ne "TOMCAT target version is ${TOMCAT_TARGET}\n\n"

echo "Retrieving files..."
rm -rf ${DOWNLOAD_FOLDER}
mkdir -p ${DOWNLOAD_FOLDER}
cd ${DOWNLOAD_FOLDER}
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.md5
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.sha1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.md5
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.sha1

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
# release files
cp apache-tomcat-${TOMCAT_TARGET}/RELEASE-NOTES ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/LICENSE ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/NOTICE ${NUXEO_HOME}/doc-tomcat
cp apache-tomcat-${TOMCAT_TARGET}/RUNNING.txt ${NUXEO_HOME}/doc-tomcat
# nuxeo version bump
sed -i 's/'$(echo "$TOMCAT_SOURCE" | sed 's/\./\\./g')'/'${TOMCAT_TARGET}'/g' ${NUXEO_HOME}/templates/nuxeo.defaults
