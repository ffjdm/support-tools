#!/bin/bash

readonly JIRA_HOST=jira.nuxeo.com
declare -a NXP_TYPES_ARRAY=("Bug" "New%20Feature" "Task" "Improvement" "Clean%20up" "Question" "User%20story" "Epic")
declare -a NXP_TYPES_LABEL_ARRAY=("Main correction(s) provided" "New Feature(s)" "Task(s)" "Improvement(s)" "Clean up(s)" "Question(s)" "User stor(y|ies)" "Epic(s)")
readonly HOTFIX_INSTALL_NOTES_URL="https://doc.nuxeo.com/60/admindoc/hotfixes-installation-notes-for-nuxeo-platform-60/"

main() {
  if [ $# -ne 2 ]; then
    usage
    exit 1
  elif [ "$1" = "xml" ] && [ -n "$2" ]; then
    getXMLReleaseNotes $2
  elif [ "$1" = "txt" ] && [ -n "$2" ]; then
    getTxtReleaseNotes $2
  else
    usage
    exit 1
  fi
}

getTxtReleaseNotes() {
  local L_VERSION=$1
  for i in $(seq 0 $((${#NXP_TYPES_ARRAY[@]} - 1))); do
    # echo -ne "[DEBUG] i=${i}\n"
    local L_SUMMARIES=$(getFixesSummaryByTypeAndVersion "${L_VERSION}" "${NXP_TYPES_ARRAY[$i]}")
    if [ -n "${L_SUMMARIES}" ]; then
      echo -ne "\t${NXP_TYPES_LABEL_ARRAY[$i]}\n"
      echo -ne "${L_SUMMARIES}\n\n"
    fi
  done
  echo -ne "\tURL\n"
  getJiraReleaseNotesUrl $L_VERSION
}

getXMLReleaseNotes() {
  local L_VERSION=$1
  local L_BRANCH=$(echo "${L_VERSION}" | cut -d "-" -f 1)

  echo -ne "<package type="hotfix" name="nuxeo-@HOTFIXVERSION@" version="@VERSION@">
  <title>Nuxeo @HOTFIXVERSION@</title>
  <description>
    Download and install the latest hotfix to keep your Nuxeo up-to-date.
    Changes will take effects after restart.

    Please make sure you consult the page Hotfixes Installation Notes
    for any additional manual action to complete the installation:
        ${HOTFIX_INSTALL_NOTES_URL}\n\n"

    for i in $(seq 0 $((${#NXP_TYPES_ARRAY[@]} - 1))); do
      # echo -ne "[DEBUG] i=${i}\n"
      local L_SUMMARIES=$(getFixesSummaryByTypeAndVersion "${L_VERSION}" "${NXP_TYPES_ARRAY[$i]}")
      if [ -n "${L_SUMMARIES}" ]; then
        echo -ne "    ${NXP_TYPES_LABEL_ARRAY[$i]}\n"
        echo -ne "$(echo "${L_SUMMARIES}" | sed 's/^\(.*\)$/    * \1/g')\n\n"
      fi
    done

echo -ne "    Complete release note is available at:\n"
echo -ne "    $(getJiraReleaseNotesUrl $L_VERSION | sed 's/&/&amp;/g')\n"
echo -ne "  </description>
  <home-page>http://www.nuxeo.com/</home-page>
  <vendor>Nuxeo</vendor>
  <installer restart="true" />
  <uninstaller restart="true" />
  <hotreload-support>false</hotreload-support>
  <nuxeo-validation>nuxeo_certified</nuxeo-validation>
  <production-state>production_ready</production-state>
  <supported>true</supported>
  <platforms>
    <platform>cap-@NUXEOVERSION@</platform>
  </platforms>
  <dependencies>
     <package>nuxeo-${L_BRANCH}-@PREVIOUSHOTFIX@:1.0.0</package>
  </dependencies>
  <visibility>MARKETPLACE</visibility>
  <license>LGPL</license>
  <license-url>http://www.gnu.org/licenses/lgpl.html</license-url>
</package>"
}

usage() {
  echo -ne "Usage: releaseNotes.sh FORMAT HF_RELEASE\n\n"
  echo -ne "FORMAT is either txt (for text output) or xml (for package.xml output)\n"
  echo -ne "HF_RELEASE is the branch and HF version combined\n\n"
  echo -ne "Examples:\n\t./releaseNotes.sh txt 6.0-HF37\n\n"
  echo -ne "\t./releaseNotes.sh xml 6.0-HF37\n\n"
}

getSection() {
  local L_HTML=$1
  local L_SECTION_NAME=$2

  echo "$L_HTML" | sed "s/<h2>\(.|\n|\r\)*?Bug\(.|\n|\r\)*?<\/h2>\(.|\n|\r\)*?<ul>\(\(.|\n|\r\)*?\)<\/ul>/\3/g"
}

getFixesSummaryByTypeAndVersion() {
  local L_VERSION=$1
  local L_TYPE=$2
  local L_JQL_QUERY="status%20in%20(Resolved%2C%20Closed)%20AND%20project%20%3D%20NXP%20AND%20fixVersion%20%3D%20${L_VERSION}%20AND%20issuetype%20%3D%20\"${L_TYPE}\""

  getJSONValues "$(getJiraJQLQuery $L_JQL_QUERY "summary")" "summary"
}

getJSONValues() {
  local L_JSON_STR=$1
  local L_FIELD=$2

  echo "${L_JSON_STR}" | grep "${L_FIELD}" | cut -d ":" -f 2 | sed 's/^\s*"\(.*\)"\s*$/\1/g'
}

getJiraJQLQuery() {
  local L_JQL_QUERY=$1
  local L_FIELDS=$2
  local L_MAX_RESULTS=$3
  local L_JIRA_HOST=${4:-${JIRA_HOST}}

  [ -n "${L_FIELDS}" ] && L_FIELDS="&fields=${L_FIELDS}"
  [ -n "${L_MAX_RESULTS}" ] && L_MAX_RESULTS="&maxResults=${L_MAX_RESULTS}"

  local L_BUILT_URL="https://${L_JIRA_HOST}/rest/api/2/search?jql=${L_JQL_QUERY}${L_FIELDS}${L_MAX_RESULTS}"
  # echo "[DEBUG] L_BUILT_URL=${L_BUILT_URL}"
  curl -nsSL -X GET -H "Content-Type: application/json" ${L_BUILT_URL} | json_pp
}

getJiraVersionsPage() {
  local L_JIRA_HOST=${1:-${JIRA_HOST}}

  curl -nsSL "https://${L_JIRA_HOST}/browse/NXP?selectedTab=com.atlassian.jira.jira-projects-plugin:versions-panel&subset=-1"
}

getJiraReleaseNotesId() {
  local L_HF_VERSION=$1

  getJiraVersionsPage | grep \"${L_HF_VERSION}\" | grep summary | sed 's/[^"]*"\([^"]*\).*/\1/' | cut -d "_" -f 2
}

getJiraReleaseNotesUrl() {
  local L_HF_VERSION=$1
  local L_JIRA_HOST=${2:-${JIRA_HOST}}
  echo "https://${L_JIRA_HOST}/secure/ReleaseNote.jspa?projectId=10011&version="$(getJiraReleaseNotesId $L_HF_VERSION)
}

getJiraReleaseNotesHtmlPage() {
  local L_HF_VERSION=$1

  curl -nsSL "$(getJiraReleaseNotesUrl $L_HF_VERSION)"
}

main "$@"
