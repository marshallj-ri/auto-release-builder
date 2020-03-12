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

get_rc()
{
  declare -a verArr=( ${1//[\.,RC]/ } )
    echo ${verArr[3]}
}

get_version_from_tag()
{
  declare -a verArr=( ${1//[\.,RC]/ } )
	echo ${verArr[0]}.${verArr[1]}.${verArr[2]}
}

increment_version ()
{
  declare -a part=( ${1//\./ } )
  declare -i   new
  declare -i carry=1

	new=${part[1]}+1
	part[1]=$new
	part[2]=0

  new_version=${part[*]}
  echo "${new_version// /.}"
} 

# ==================== MAIN ====================

# Ensure that the GITHUB_TOKEN secret is included
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi
if [[ ${GITHUB_REF} = "refs/heads/development" ]]; then
	branch=$(echo ${GITHUB_REF} | awk -F'/' '{print $3}')
	last_tag_number=$(git tag -l 4.* --sort -version:refname$(git rev-list --max-count=1))
	echo "The last tag number was: $last_tag_number"
	if [[ ${GITHUB_REF} = "refs/heads/development" ]]; then
		prerelease=true
	
		# Create new tag.
		if [[ $last_tag_number == *"RC"* ]]; then
			echo "is rc"
			echo "$last_tag_number end"
			current_rc_version=$(get_rc $last_tag_number)
			declare -i next_rc_version=$current_rc_version+1
			echo $next_rc_version
			version="$(get_version_from_tag $last_tag_number)"
			new_tag="${version}RC${next_rc_version}"
			echo $new_tag
			echo "The new tag number is: $new_tag"
		else
			echo "is not rc"
			new_version=$(increment_version $last_tag_number)
			new_tag="${new_version}RC1"
			echo "The new tag number is: $new_tag"
		fi
	fi

	echo "The new git tag number is: $new_tag"
	git_tag="${new_tag}"
	echo ${git_tag}
	release_name="${new_tag//RC/ Release Candidate }"
	echo ${release_name}
	request_create_release
else
	echo "This Action run only in master or development branch"
	exit 0
fi
