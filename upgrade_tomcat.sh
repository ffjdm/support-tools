#!/bin/bash

# Upgrades Nuxeo Tomcat to latest version

# TODOs
# make the NUXEO_HOME a parameter
# make TOMCAT_TARGET an optional parameter

TOMCAT_ARCHIVE_URL="https://archive.apache.org/dist/tomcat/tomcat-7"
TOMCAT_LATEST_URL="http://www.apache.org/dist/tomcat/tomcat-7"
WORK_FOLDER=/tmp
DOWNLOAD_FOLDER=${WORK_FOLDER}/nuxeo_downloads

NUXEO_HOME=/Users/ffischer/Downloads/tomcat/nuxeo-cap-7.10-tomcat

TOMCAT_SOURCE=$(java -cp ${NUXEO_HOME}/lib/catalina.jar org.apache.catalina.util.ServerInfo | grep "Server number" | sed 's/.*\(7\.0.[0-9]*\).*/\1/g')
TOMCAT_NUXEO_DEFAULT=$(cat ${NUXEO_HOME}/templates/nuxeo.defaults | grep tomcat.version | cut -d "=" -f 2)
# autodetects latest version
#TOMCAT_TARGET=$(curl -sSL ${TOMCAT_LATEST_URL} | grep href=\"v | sed 's/.*href="v\(7.0.[0-9]*\).*/\1/g')
TOMCAT_TARGET=${TOMCAT_TARGET:-7.0.74} # fallback to 7.0.75 if autodetection failed

echo "TOMCAT source version (from libs) is ${TOMCAT_SOURCE}"
echo "TOMCAT source version (from nuxeo.defaults) is ${TOMCAT_NUXEO_DEFAULT}"
if [ "${TOMCAT_SOURCE}" = "${TOMCAT_NUXEO_DEFAULT}" ]; then
  echo "TOMCAT source versions match!"
else
  echo "ERROR: TOMCAT source version don't match!"
  exit 1
fi
echo -ne "TOMCAT target version is ${TOMCAT_TARGET}\n\n"

echo "Retrieving files..."
rm -rf ${DOWNLOAD_FOLDER}
mkdir -p ${DOWNLOAD_FOLDER}
cd ${DOWNLOAD_FOLDER}
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5 || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1 || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.md5 || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.sha1 || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.md5 || exit 2
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.sha1 || exit 2

echo "Checking archives..."
# fix wrong md5 and sha1 file content
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.md5; echo >> tomcat-juli-adapters.jar.md5
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.sha1; echo >> tomcat-juli-adapters.jar.sha1
sed -i 's/\*/ /g' tomcat-juli.jar.md5; echo >> tomcat-juli.jar.md5
sed -i 's/\*/ /g' tomcat-juli.jar.sha1; echo >> tomcat-juli.jar.sha1
# perform checks
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
