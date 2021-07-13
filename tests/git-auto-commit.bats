#!/usr/bin/env bats

load '../node_modules/bats-support/load'
load '../node_modules/bats-assert/load'

setup() {
    # Define Paths for local repository used during tests
    export FAKE_LOCAL_REPOSITORY="${BATS_TEST_DIRNAME}/tests_local_repository"
    export FAKE_REMOTE="${BATS_TEST_DIRNAME}/tests_remote_repository"
    export FAKE_TEMP_LOCAL_REPOSITORY="${BATS_TEST_DIRNAME}/tests_clone_of_remote_repository"

    # Set default INPUT variables used by the GitHub Action
    export INPUT_REPOSITORY="${FAKE_LOCAL_REPOSITORY}"
    export INPUT_COMMIT_MESSAGE="Commit Message"
    export INPUT_BRANCH="master"
    export INPUT_COMMIT_OPTIONS=""
    export INPUT_ADD_OPTIONS=""
    export INPUT_STATUS_OPTIONS=""
    export INPUT_FILE_PATTERN="."
    export INPUT_COMMIT_USER_NAME="Test Suite"
    export INPUT_COMMIT_USER_EMAIL="test@github.com"
    export INPUT_COMMIT_AUTHOR="Test Suite <test@users.noreply.github.com>"
    export INPUT_TAGGING_MESSAGE=""
    export INPUT_PUSH_OPTIONS=""
    export INPUT_SKIP_DIRTY_CHECK=false
    export INPUT_SKIP_FETCH=false
    export INPUT_DISABLE_GLOBBING=false

    # Configure Git
    if [[ -z $(git config user.name) ]]; then
        git config --global user.name "Test Suite"
        git config --global user.email "test@github.com"
    fi

    # Create and setup some fake repositories for testing
    _setup_fake_remote_repository
    _setup_local_repository
}

teardown() {
    rm -rf "${FAKE_LOCAL_REPOSITORY}"
    rm -rf "${FAKE_REMOTE}"
    rm -rf "${FAKE_TEMP_LOCAL_REPOSITORY}"
}

# Create a fake remote repository which tests can push against
_setup_fake_remote_repository() {
    # Create the bare repository, which will act as our remote/origin
    rm -rf "${FAKE_REMOTE}";
    mkdir "${FAKE_REMOTE}";
    cd "${FAKE_REMOTE}";
    git init --bare;

    # Clone the remote repository to a temporary location.
    rm -rf "${FAKE_TEMP_LOCAL_REPOSITORY}"
    git clone "${FAKE_REMOTE}" "${FAKE_TEMP_LOCAL_REPOSITORY}"

    # Create some files, commit them and push them to the remote repository
    touch "${FAKE_TEMP_LOCAL_REPOSITORY}"/remote-files{1,2,3}.txt
    cd "${FAKE_TEMP_LOCAL_REPOSITORY}";
    git add .;
    git commit --quiet -m "Init Remote Repository";
    git push origin master;
}

# Clone our fake remote repository and set it up for testing
_setup_local_repository() {
    # Clone remote repository. In this repository we will do our testing
    rm -rf "${FAKE_LOCAL_REPOSITORY}"
    git clone "${FAKE_REMOTE}" "${FAKE_LOCAL_REPOSITORY}"

    cd "${FAKE_LOCAL_REPOSITORY}";
}

# Run the main code related to this GitHub Action
git_auto_commit() {
    bash "${BATS_TEST_DIRNAME}"/../entrypoint.sh
}

@test "It detects changes, commits them and pushes them to the remote repository" {
    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_REPOSITORY value: ${INPUT_REPOSITORY}"
    assert_line "::set-output name=changes_detected::true"
    assert_line "INPUT_BRANCH value: master"
    assert_line "INPUT_FILE_PATTERN: ."
    assert_line "INPUT_COMMIT_OPTIONS: "
    assert_line "::debug::Apply commit options "
    assert_line "INPUT_TAGGING_MESSAGE: "
    assert_line "No tagging message supplied. No tag will be added."
    assert_line "INPUT_PUSH_OPTIONS: "
    assert_line "::debug::Apply push options "
    assert_line "::debug::Push commit to remote branch master"
}

@test "It detects when files have been deleted, commits changes and pushes them to the remote repository" {
    rm -rf "${FAKE_LOCAL_REPOSITORY}"/remote-files1.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_REPOSITORY value: ${INPUT_REPOSITORY}"
    assert_line "::set-output name=changes_detected::true"
    assert_line "INPUT_BRANCH value: master"
    assert_line "INPUT_FILE_PATTERN: ."
    assert_line "INPUT_COMMIT_OPTIONS: "
    assert_line "::debug::Apply commit options "
    assert_line "INPUT_TAGGING_MESSAGE: "
    assert_line "No tagging message supplied. No tag will be added."
    assert_line "INPUT_PUSH_OPTIONS: "
    assert_line "::debug::Apply push options "
    assert_line "::debug::Push commit to remote branch master"
}

@test "It applies INPUT_STATUS_OPTIONS when running dirty check" {
    INPUT_STATUS_OPTIONS="--untracked-files=no"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.php

    run git_auto_commit

    assert_success

    assert_line "INPUT_REPOSITORY value: ${INPUT_REPOSITORY}"
    assert_line "::set-output name=changes_detected::false"
    assert_line "Working tree clean. Nothing to commit."
}

@test "It prints a 'Nothing to commit' message in a clean repository" {
    run git_auto_commit

    assert_success

    assert_line "INPUT_REPOSITORY value: ${INPUT_REPOSITORY}"
    assert_line "::set-output name=changes_detected::false"
    assert_line "Working tree clean. Nothing to commit."
}

@test "If SKIP_DIRTY_CHECK is set to true on a clean repo it fails to push" {
    INPUT_SKIP_DIRTY_CHECK=true

    run git_auto_commit

    assert_failure

    assert_line "INPUT_REPOSITORY value: ${INPUT_REPOSITORY}"
    assert_line "::set-output name=changes_detected::true"

    assert_line "::set-output name=changes_detected::true"
    assert_line "INPUT_BRANCH value: master"
    assert_line "INPUT_FILE_PATTERN: ."
    assert_line "INPUT_COMMIT_OPTIONS: "
    assert_line "::debug::Apply commit options "
}

@test "It applies INPUT_ADD_OPTIONS when adding files" {
    INPUT_FILE_PATTERN=""
    INPUT_STATUS_OPTIONS="--untracked-files=no"
    INPUT_ADD_OPTIONS="-u"

    date > "${FAKE_LOCAL_REPOSITORY}"/remote-files1.txt
    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.php

    run git_auto_commit

    assert_success

    assert_line "INPUT_STATUS_OPTIONS: --untracked-files=no"
    assert_line "INPUT_ADD_OPTIONS: -u"
    assert_line "INPUT_FILE_PATTERN: "
    assert_line "::debug::Push commit to remote branch master"

    # Assert that PHP files have not been added.
    run git status
    assert_output --partial 'new-file-1.php'
}

@test "It applies INPUT_FILE_PATTERN when creating commit" {
    INPUT_FILE_PATTERN="*.txt *.html"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.php
    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.html

    run git_auto_commit

    assert_success

    assert_line "INPUT_FILE_PATTERN: *.txt *.html"
    assert_line "::debug::Push commit to remote branch master"

    # Assert that PHP files have not been added.
    run git status
    assert_output --partial 'new-file-1.php'
}

@test "It applies INPUT_COMMIT_OPTIONS when creating commit" {
    INPUT_COMMIT_OPTIONS="--no-verify --signoff"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_COMMIT_OPTIONS: --no-verify --signoff"
    assert_line "::debug::Push commit to remote branch master"

    # Assert last commit was signed off
    run git log -n 1
    assert_output --partial "Signed-off-by:"
}

@test "It applies commit user and author settings" {
    INPUT_COMMIT_USER_NAME="A Single Test"
    INPUT_COMMIT_USER_EMAIL="single-test@github.com"
    INPUT_COMMIT_AUTHOR="A Single Test <single@users.noreply.github.com>"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_COMMIT_USER_NAME: A Single Test";
    assert_line "INPUT_COMMIT_USER_EMAIL: single-test@github.com";
    assert_line "INPUT_COMMIT_AUTHOR: A Single Test <single@users.noreply.github.com>";
    assert_line "::debug::Push commit to remote branch master"

    # Asser last commit was made by the defined user/author
    run git log -1 --pretty=format:'%ae'
    assert_output --partial "single@users.noreply.github.com"

    run git log -1 --pretty=format:'%an'
    assert_output --partial "A Single Test"

    run git log -1 --pretty=format:'%cn'
    assert_output --partial "A Single Test"

    run git log -1 --pretty=format:'%ce'
    assert_output --partial "single-test@github.com"
}

@test "It creates a tag with the commit" {
    INPUT_TAGGING_MESSAGE="v1.0.0"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_TAGGING_MESSAGE: v1.0.0"
    assert_line "::debug::Create tag v1.0.0"
    assert_line "::debug::Push commit to remote branch master"

    # Assert a tag v1.0.0 has been created
    run git tag
    assert_output v1.0.0

    run git ls-remote --tags --refs
    assert_output --partial refs/tags/v1.0.0

    # Assert that the commit has been pushed with --force and
    # sha values are equal on local and remote
    current_sha="$(git rev-parse --verify --short master)"
    remote_sha="$(git rev-parse --verify --short origin/master)"

    assert_equal $current_sha $remote_sha
}

@test "It applies INPUT_PUSH_OPTIONS when pushing commit to remote" {

    touch "${FAKE_TEMP_LOCAL_REPOSITORY}"/newer-remote-files{1,2,3}.txt
    cd "${FAKE_TEMP_LOCAL_REPOSITORY}";
    git add .;
    git commit --quiet -m "Add more remote files";
    git push origin master;


    INPUT_PUSH_OPTIONS="--force"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_PUSH_OPTIONS: --force"
    assert_line "::debug::Apply push options --force"
    assert_line "::debug::Push commit to remote branch master"

    # Assert that the commit has been pushed with --force and
    # sha values are equal on local and remote
    current_sha="$(git rev-parse --verify --short master)"
    remote_sha="$(git rev-parse --verify --short origin/master)"

    assert_equal $current_sha $remote_sha
}

@test "It can checkout a different branch" {
    # Create foo-branch and then immediately switch back to master
    git checkout -b foo
    git checkout master

    INPUT_BRANCH="foo"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_BRANCH value: foo"
    assert_line "::debug::Push commit to remote branch foo"

    # Assert a new branch "foo" exists on remote
    run git ls-remote --heads
    assert_output --partial refs/heads/foo
}

@test "It uses existing branch name when pushing when INPUT_BRANCH is empty" {
    INPUT_BRANCH=""

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_BRANCH value: "
    assert_line --partial "::debug::git push origin"

    # Assert that branch "master" was updated on remote
    current_sha="$(git rev-parse --verify --short master)"
    remote_sha="$(git rev-parse --verify --short origin/master)"

    assert_equal $current_sha $remote_sha
}

@test "It uses existing branch when INPUT_BRANCH is empty and INPUT_TAGGING_MESSAGE is set" {
    INPUT_BRANCH=""
    INPUT_TAGGING_MESSAGE="v2.0.0"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_TAGGING_MESSAGE: v2.0.0"
    assert_line "::debug::Create tag v2.0.0"
    assert_line "::debug::git push origin --tags"

    # Assert a tag v2.0.0 has been created
    run git tag
    assert_output v2.0.0

    # Assert tag v2.0.0 has been pushed to remote
    run git ls-remote --tags --refs
    assert_output --partial refs/tags/v2.0.0
}

@test "If SKIP_FETCH is true git-fetch will not be called" {

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    INPUT_SKIP_FETCH=true

    run git_auto_commit

    assert_success

    assert_line "::debug::git-fetch has not been executed"
}

@test "It pushes generated commit and tag to remote and actually updates the commit shas" {
    INPUT_BRANCH=""
    INPUT_TAGGING_MESSAGE="v2.0.0"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_TAGGING_MESSAGE: v2.0.0"
    assert_line "::debug::Create tag v2.0.0"
    assert_line "::debug::git push origin --tags"

    # Assert a tag v2.0.0 has been created
    run git tag
    assert_output v2.0.0

    # Assert tag v2.0.0 has been pushed to remote
    run git ls-remote --tags --refs
    assert_output --partial refs/tags/v2.0.0

    # Assert that branch "master" was updated on remote
    current_sha="$(git rev-parse --verify --short master)"
    remote_sha="$(git rev-parse --verify --short origin/master)"

    assert_equal $current_sha $remote_sha
}

@test "It pushes generated commit and tag to remote branch and updates commit sha" {
    # Create "a-new-branch"-branch and then immediately switch back to master
    git checkout -b a-new-branch
    git checkout master

    INPUT_BRANCH="a-new-branch"
    INPUT_TAGGING_MESSAGE="v2.0.0"

    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-{1,2,3}.txt

    run git_auto_commit

    assert_success

    assert_line "INPUT_TAGGING_MESSAGE: v2.0.0"
    assert_line "::debug::Create tag v2.0.0"
    assert_line "::debug::Push commit to remote branch a-new-branch"

    # Assert a tag v2.0.0 has been created
    run git tag
    assert_output v2.0.0

    # Assert tag v2.0.0 has been pushed to remote
    run git ls-remote --tags --refs
    assert_output --partial refs/tags/v2.0.0

    # Assert that branch "a-new-branch" was updated on remote
    current_sha="$(git rev-parse --verify --short a-new-branch)"
    remote_sha="$(git rev-parse --verify --short origin/a-new-branch)"

    assert_equal $current_sha $remote_sha
}

@test "It does not expand wildcard glob when using INPUT_PATTERN and INPUT_DISABLE_GLOBBING in git-status and git-add" {

    # Create additional files in a nested directory structure
    echo "Create Additional files";
    touch "${FAKE_LOCAL_REPOSITORY}"/new-file-a.py
    mkdir "${FAKE_LOCAL_REPOSITORY}"/nested
    touch "${FAKE_LOCAL_REPOSITORY}"/nested/new-file-b.py

    # Commit changes
    echo "Commit changes before running git_auto_commit";
    cd "${FAKE_LOCAL_REPOSITORY}";
    git add . > /dev/null;
    git commit --quiet -m "Init Remote Repository";
    git push origin master > /dev/null;

    # Make nested file dirty
    echo "foo-bar" > "${FAKE_LOCAL_REPOSITORY}"/nested/new-file-b.py;

    # ---

    INPUT_FILE_PATTERN="*.py"
    INPUT_DISABLE_GLOBBING=true

    run git_auto_commit

    assert_success

    assert_line "INPUT_FILE_PATTERN: *.py"
    assert_line "::debug::Push commit to remote branch master"

    # Assert that the updated py file has been commited.
    run git status
    refute_output --partial 'nested/new-file-b.py'
}
