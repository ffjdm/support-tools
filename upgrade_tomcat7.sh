#!/bin/bash

# Upgrades Nuxeo Tomcat

TOMCAT_ARCHIVE_URL="https://archive.apache.org/dist/tomcat/tomcat-7"
TOMCAT_LATEST_URL="http://www.apache.org/dist/tomcat/tomcat-7"

usage() {
  echo "Usage:"
  echo -e "\t./upgrade_tomcat7.sh NUXEO_HOME [TOMCAT_TARGET_VERSION]"
  echo
  echo "Note: If no target version is specified the latest one will be retrieved from the Tomcat site"
  echo
  echo "Examples:"
  echo -e "\t./upgrade_tomcat7.sh /Users/ffischer/nuxeo-cap-7.10-tomcat"
  echo -e "\t./upgrade_tomcat7.sh /Users/ffischer/nuxeo-cap-7.10-tomcat 7.0.76"
}

if [ $# -eq 0 -o $# -gt 3 ]; then
  usage
  exit 1
fi

# does the Nuxeo location seem valid?
if [ ! -f "$1/templates/nuxeo.defaults" ]; then
  echo "ERROR: Cannot find nuxeo.defaults file. Please check the Nuxeo location."
  echo
  exit 1
fi
NUXEO_HOME=$1

if [ -z "$2" ]; then
  # autodetects latest version
  TOMCAT_TARGET=$(curl -sSL ${TOMCAT_LATEST_URL} | grep href=\"v | sed 's/.*href="v\(7.0.[0-9]*\).*/\1/g')
  TOMCAT_TARGET=${TOMCAT_TARGET:-7.0.75} # fallback to 7.0.75 if autodetection failed
else
  # check the TOMCAT version exists
  VERSIONS_FOUND=$(curl -sSL ${TOMCAT_ARCHIVE_URL} | grep ${2} | wc -l | sed 's/^\s*\(.*\)$/\1/g')
  if [ "$VERSIONS_FOUND" -ne 1 ]; then
    echo -ne "Cannot find Tomcat version ${2}\n\n"
    exit 1
  else
    TOMCAT_TARGET=$2
  fi
fi

WORK_FOLDER=`mktemp -d -q /tmp/$(basename $0).XXXXXX`
if [ $? -ne 0 ]; then
  echo "ERROR: Cannot create temp file, exiting..."
  exit 1
fi

TOMCAT_SOURCE=$(java -cp "${NUXEO_HOME}/lib/catalina.jar" org.apache.catalina.util.ServerInfo | grep "Server number" | sed 's/.*\(7\.0.[0-9]*\).*/\1/g')
TOMCAT_NUXEO_DEFAULT=$(cat "${NUXEO_HOME}/templates/nuxeo.defaults" | grep tomcat.version | cut -d "=" -f 2)

echo "NUXEO_HOME is ${NUXEO_HOME}"
echo "TEMPORARY WORK FOLDER is ${WORK_FOLDER}"
echo "TOMCAT source version (from libs) is ${TOMCAT_SOURCE}"
echo "TOMCAT source version (from nuxeo.defaults) is ${TOMCAT_NUXEO_DEFAULT}"
if [ "${TOMCAT_SOURCE}" = "${TOMCAT_NUXEO_DEFAULT}" ]; then
  echo "TOMCAT source versions match!"
else
  echo "ERROR: TOMCAT source versions don't match!"
  exit 1
fi
echo "TOMCAT target version is ${TOMCAT_TARGET}"
echo

echo "Retrieving files..."
rm -rf "${WORK_FOLDER}"
mkdir -p "${WORK_FOLDER}"
cd "${WORK_FOLDER}"
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5 || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1 || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.md5 || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli-adapters.jar.sha1 || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.md5 || exit 1
wget ${TOMCAT_ARCHIVE_URL}/v${TOMCAT_TARGET}/bin/extras/tomcat-juli.jar.sha1 || exit 1

echo "Checking archives..."
# fix wrong md5 and sha1 file content
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5
sed -i 's/\*/ /g' apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1; echo >> apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.md5; echo >> tomcat-juli-adapters.jar.md5
sed -i 's/\*/ /g' tomcat-juli-adapters.jar.sha1; echo >> tomcat-juli-adapters.jar.sha1
sed -i 's/\*/ /g' tomcat-juli.jar.md5; echo >> tomcat-juli.jar.md5
sed -i 's/\*/ /g' tomcat-juli.jar.sha1; echo >> tomcat-juli.jar.sha1
# perform checks
md5sum -c apache-tomcat-${TOMCAT_TARGET}.tar.gz.md5 || exit 1
shasum -c apache-tomcat-${TOMCAT_TARGET}.tar.gz.sha1 || exit 1
md5sum -c tomcat-juli-adapters.jar.md5 || exit 1
shasum -c tomcat-juli-adapters.jar.sha1 || exit 1
md5sum -c tomcat-juli.jar.md5 || exit 1
shasum -c tomcat-juli.jar.sha1 || exit 1

echo "Patching Nuxeo..."
# upgrading files from core distribution
tar zxf apache-tomcat-${TOMCAT_TARGET}.tar.gz
cp apache-tomcat-${TOMCAT_TARGET}/lib/* "${NUXEO_HOME}/lib"
cp apache-tomcat-${TOMCAT_TARGET}/bin/*.jar "${NUXEO_HOME}/bin"
cp apache-tomcat-${TOMCAT_TARGET}/bin/catalina-tasks.xml "${NUXEO_HOME}/bin"
cp apache-tomcat-${TOMCAT_TARGET}/lib/tomcat-jdbc.jar "${NUXEO_HOME}/nxserver/lib/tomcat-jdbc-${TOMCAT_TARGET}.jar"
rm "${NUXEO_HOME}/nxserver/lib/tomcat-jdbc-${TOMCAT_SOURCE}.jar"
cp apache-tomcat-${TOMCAT_TARGET}/bin/tomcat-juli.jar "${NUXEO_HOME}/nxserver/lib/tomcat-juli-${TOMCAT_TARGET}.jar"
rm "${NUXEO_HOME}/nxserver/lib/tomcat-juli-${TOMCAT_SOURCE}.jar"
# upgrading files from extras
cp tomcat-juli.jar "${NUXEO_HOME}/bin"
cp tomcat-juli-adapters.jar "${NUXEO_HOME}/lib"
# release files
cp apache-tomcat-${TOMCAT_TARGET}/RELEASE-NOTES "${NUXEO_HOME}/doc-tomcat"
cp apache-tomcat-${TOMCAT_TARGET}/LICENSE "${NUXEO_HOME}/doc-tomcat"
cp apache-tomcat-${TOMCAT_TARGET}/NOTICE "${NUXEO_HOME}/doc-tomcat"
cp apache-tomcat-${TOMCAT_TARGET}/RUNNING.txt "${NUXEO_HOME}/doc-tomcat"
# nuxeo version bump
sed -i 's/'$(echo "$TOMCAT_SOURCE" | sed 's/\./\\./g')'/'${TOMCAT_TARGET}'/g' "${NUXEO_HOME}/templates/nuxeo.defaults"
