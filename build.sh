#!/bin/sh
set -eu

OUTDIR=~/output/

cd
pwd

# Clone Opencast repository
rm -rf opencast || :
git clone https://github.com/opencast/opencast.git
cd opencast

# Get the branches
BRANCHES="develop
$(git branch -a |
    sed -e 's#^.*remotes/origin/\(r/[2-9]*\.*[0-9]*\.x\).*$#\1#;tx;d;:x' |
    sort -r)"

VERSIONS="var versions = ['develop'"

for branch in ${BRANCHES}
do
    echo
    python -c "print('='*10 + ' Building docs for ${branch} ' + '='*50)"
    echo

    # install mkdocs
    if echo "$branch" | grep -q '^r/[234]\.'; then
        # deliberately install an old version for the old docs
        pip -q install mkdocs==0.16.3
    else
        pip -q install mkdocs mkdocs-windmill markdown_inline_graphviz_extension
    fi

    [ "develop" = "${branch}" ] || VERSIONS="${VERSIONS}, '${branch}'"
    git reset --hard HEAD
    git clean -fdx
    git checkout "origin/${branch}"

    echo "Building documentation for ${branch}"
    for target in admin developer user
    do
        (
            set -eu
            cd ~/opencast/docs/guides/"${target}"
            python -m mkdocs build
            mkdir -p "${OUTDIR}/${branch}"
            mv site "${OUTDIR}/${branch}/${target}"
        )
    done

    # Add index page
    if [ "${branch}" = 'develop' ]; then
        cp ~/opencast/docs/guides/index.html "${OUTDIR}"
    fi

    # Remove mkdocs to ensure we can install the version we need
    pip uninstall -y mkdocs
done

echo "${VERSIONS}];" > "${OUTDIR}/versions.js"

# Hide all exept develop and the last 3 release branches from search engines
# shellcheck disable=SC2016
echo "$BRANCHES" |\
    tail -n +5 |\
    sed 's_^.*$_USER-agent: *\nDisallow: /\0\n_g' > "${OUTDIR}/robots.txt"


echo
python -c "print('='*10 + ' Deployment ' + '='*50)"
echo

# Prepare Github SSH key
echo "${GITHUB_DEPLOY_KEY}" | base64 -d > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts

set -x

# Get target repository
cd
rm -rf docs.opencast.org || :
git clone git@github.com:opencast/docs.opencast.org.git
cd docs.opencast.org

# Prepare gh-pages branch
if git checkout gh-pages; then
    git ls-files | while read -r f; do git rm -rf "$f"; done
else
    git checkout --orphan gh-pages
    git ls-files | while read -r f; do rm -f "$f"; git rm --cached "$f"; done
fi

# Add new content
mv "${OUTDIR}"/* .
echo docs.opencast.org > CNAME
git add ./*
git commit -m "Documentation ($(date))"
git push origin gh-pages
