#!/bin/bash
################################################################################
# Descrição:
#   Script Github Actions to create a new release automatically
################################################################################

set -e
set -o pipefail

# ============================================
# Function to create a new release in Github API
# ============================================
request_create_release(){
	local json_body='{
	  "tag_name": "@tag_name@",
	  "target_commitish": "@branch@",
	  "name": "@release_name@",
	  "body": "@description@",
	  "draft": false,
	  "prerelease": @prerelease@
	}'
		
	json_body=$(echo "$json_body" | sed "s/@tag_name@/$git_tag/")
	json_body=$(echo "$json_body" | sed "s/@branch@/$branch/")
	json_body=$(echo "$json_body" | sed "s/@release_name@/$release_name/")
	json_body=$(echo "$json_body" | sed "s/@description@/$DESCRIPTION/")
	json_body=$(echo "$json_body" | sed "s/@prerelease@/$prerelease/")
		
	curl --request POST \
	  --url https://api.github.com/repos/${GITHUB_REPOSITORY}/releases \
	  --header "Authorization: Bearer $GITHUB_TOKEN" \
	  --header 'Content-Type: application/json' \
	  --data "$json_body"
}

request_create_ticket(){
	local json_body='{
		"fields": {
			"project": {
				"key":"SI"
			},
			"summary": "ARB: Deploy @release_name@ to @environment@",
			"description": "https://github.com/reapit/rpw/releases/tag/@tag@\nPlease deploy to:\n/mnt/netapp/code/webservice/release-groups/@environment@/\n/mnt/netapp/code/web/release-groups/@environment@/\n/mnt/netapp/code/tracker/release-groups/@environment@/\n/mnt/netapp/code/rda/release-groups/@environment@/\n/mnt/netapp/code/services/release-groups/@environment@/\n/mnt/netapp/code/propertypulse/release-groups/@environment@",
			"issuetype":
				{
					"name": "Deployment"
				}
		}	
	}'
	
	if [[ $prerelease ]]; then
		local environment='test'
	else 
		local environment='live'
	fi
	
	json_body=$(echo "$json_body" | sed "s/@tag@/$git_tag/")
	json_body=$(echo "$json_body" | sed "s/@release_name@/$release_name/")
	json_body=$(echo "$json_body" | sed "s/@environment@/$environment/g")
	
	curl --request POST \
		--url 'https://reapit.atlassian.net/rest/api/2/issue' \
		--user "${JIRA_USER}:${JIRA_API_KEY}" \
		--header 'Accept: application/json' \
		--header 'Content-Type: application/json' \
		--data "$json_body"
}

increment_version ()
{
  declare -a part=( ${1//\./ } )
  declare    new
  declare -i carry=1

  for (( CNTR=${#part[@]}-2; CNTR>=0; CNTR-=1 )); do
    len=${#part[CNTR]}
    new=$((part[CNTR]+carry))
    [ ${#new} -gt $len ] && carry=1 || carry=0
    [ $CNTR -gt 0 ] && part[CNTR]=${new: -len} || part[CNTR]=${new}
  done
  new="${part[*]}"
  echo -e "${new// /.}"
} 

# ==================== MAIN ====================

# Ensure that the GITHUB_TOKEN secret is included
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi
if [[ ${GITHUB_REF} = "refs/heads/master" || ${GITHUB_REF} = "refs/heads/development" ]]; then
	branch=$(echo ${GITHUB_REF} | awk -F'/' '{print $3}')
	last_tag_number=$(git describe --tags $(git rev-list --tags --max-count=1))
	echo "The last tag number was: $last_tag_number"
	if [[ ${GITHUB_REF} = "refs/heads/development" ]]; then
		prerelease=true
	
		# Create new tag.
		if [[ $last_tag_number == *"RC"* ]]; then
			current_rc_version="${last_tag_number: -1}"
			next_rc_version=$((current_rc_version+1))
			new_tag="${last_tag_number::-1}$next_rc_version"
		else
			new_version=$(increment_version $last_tag_number)
			new_tag="${new_version}RC1"
		fi	
	else
		prerelease=false
		echo "LOG: Merging into Master branch"
		if [[ $last_tag_number == *"RC"* ]]; then
			modified_tag="${last_tag_number%RC*}"
			new_tag=$modified_tag
			echo "The last tag was an RC version"
			echo "The new tag and release is: $new_tag"
		else
			new_tag=$(increment_version $last_tag_number)
			echo "The last tag was not an RC version"
			echo "The new tag and release is: $new_tag"
		fi
		
		last_commit=$(git log -1 --pretty=%B)
		echo "The last commit was: $last_commit"
		if [[ -n "$last_commit" && "$last_commit" == *"hotfix-"* ]]; then
			#Hotfixes will remain a manual process as they are a rare occurance
			#It would also make this automation very combersome.
			echo "LOG: Release cancelled as change is a hot fix and should be done manually"
			exit 0
		fi
	fi

	git_tag="${new_tag}"
	release_name="${new_tag//RC/ Release Candidate }"
	request_create_release
	request_create_ticket
else
	echo "This Action run only in master or development branch"
	exit 0
fi
