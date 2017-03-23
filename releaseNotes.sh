#!/bin/bash

readonly JIRA_HOST=jira.nuxeo.com
declare -a NXP_TYPES_ARRAY=("Bug" "New%20Feature" "Task" "Improvement" "Clean%20up" "Question" "User%20story" "Epic")

main() {
  if [ $# -ne 1 ]; then
    echo -ne "Usage: releaseNotes.sh HF_RELEASE\n\nExample: ./releaseNotes.sh 6.0-HF37\n\n"
    exit 1
  fi
  # local HTML_REL_NOTES=$(getJiraReleaseNotesHtmlPage "7.10-HF23" | sed -n "/<textarea.*>/,/<\/textarea>/p")
  # echo "$HTML_REL_NOTES"
  # getSection "$HTML_REL_NOTES" "Bugs"
  # <h2>(.|\n|\r)*?Bug(.|\n|\r)*?<\/h2>

# getJiraJQLQuery "status%20in%20(Resolved%2C%20Closed)%20AND%20project%20%3D%20NXP%20AND%20fixVersion%20%3D%206.0-HF37%20AND%20issuetype%20%3D%20\"re\"" "summary"

# exit 1

  for i in "${NXP_TYPES_ARRAY[@]}"; do
    # echo -ne "[DEBUG] i=${i}\n"
    local L_SUMMARIES=$(getFixesSummaryByTypeAndVersion "${1}" "${i}")
    if [ -n "${L_SUMMARIES}" ]; then
      echo -ne "\t${i}\n"
      echo -ne "${L_SUMMARIES}\n\n"
    fi
  done
  # echo -ne "\tBugs\n"
  # getFixesSummaryByTypeAndVersion "6.0-HF37" "Bug"
  # echo -ne "\n\tImprovements\n"
  # getFixesSummaryByTypeAndVersion "6.0-HF37" "Improvement"
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

    # echo $L_REQUEST_URL
    # curl -n "${L_REQUEST_URL}"
    # curl -n -X GET -H "Content-Type: application/json" "https://${JIRA_HOST}/rest/api/2/search?jql="
#    curl -n -s -X GET -H "Content-Type: application/json" -H "Cache-Control: no-cache" "${L_REQUEST_URL}" # | json_pp
    getJSONValues "$(getJiraJQLQuery $L_JQL_QUERY "summary")" "summary"
    # getJiraJQLQuery $L_JQL_QUERY "summary"
}

getJSONValues() {
  local L_JSON_STR=$1
  local L_FIELD=$2

  # echo "${L_JSON_STR}" | grep "${L_FIELD}" | cut -d "\"" -f 4
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
    curl -s "https://${JIRA_HOST}/browse/NXP?selectedTab=com.atlassian.jira.jira-projects-plugin:versions-panel&subset=-1"
    return $?
}

getJiraReleaseNotesId() {
    local version=$1
    getJiraVersionsPage | grep $version | grep summary | sed 's/[^"]*"\([^"]*\).*/\1/' | cut -d "_" -f 2
    return $?
}

getJiraReleaseNotesUrl() {
    local version=$1
    echo "https://${JIRA_HOST}/secure/ReleaseNote.jspa?projectId=10011&version="$(getJiraReleaseNotesId $version)
    return $?
}

getJiraReleaseNotesHtmlPage() {
    local version=$1
    curl -s "$(getJiraReleaseNotesUrl $version)"
    return $?
}

main "$@"
