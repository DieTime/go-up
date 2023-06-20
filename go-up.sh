#!/bin/bash

SUDOCMD=""
WGETCMD="wget -qO-"
CURLCMD="curl -sL"
EXTRACTCMD="tar -xzf - --strip-components=1 -C"

GOBIN=$(which go 2> /dev/null)

if [[ -z "$GOBIN" ]]
then
    echo "❌ Go not installed, nothing to update"
    exit 1
fi

GOROOT=$($GOBIN env GOROOT 2> /dev/null)
GOPATH=$($GOBIN env GOPATH 2> /dev/null)

if [[ -z "$GOROOT" ]]
then
    echo "❌ Could't find \$GOROOT environment variable"
    exit 1
fi

GOVERSION=$($GOBIN env GOVERSION 2> /dev/null)
GOVERSIONPRETTY=${GOVERSION#"go"}

if [[ -z "$GOVERSION" ]]
then
    echo "❌ Could't find \$GOVERSION environment variable"
    exit 1
fi

if [[ -z "$(which wget 2> /dev/null)" ]] && [[ -z "$(which curl 2> /dev/null)" ]]
then
    echo "❌ Unable to update go to latest version, please install wget or curl"
    exit 1
fi

GOLATESTURL="https://go.dev/VERSION?m=text"
GOLATEST=$($WGETCMD "$GOLATESTURL" 2> /dev/null || $CURLCMD "$GOLATESTURL" 2> /dev/null)
GOLATESTPRETTY=${GOLATEST#"go"}

if [[ -z "$GOLATEST" ]]
then
    echo "❌ Could't fetch latest golang version"
    exit 1
fi

if [[ "$GOVERSION" == "$GOLATEST" ]]
then
    echo "👍 You already have the latest go with version $GOVERSIONPRETTY, no update required"
    exit 0
fi

case $(uname) in
    Linux)  GOROOTOWNER=$(stat -c "%U" $GOROOT 2> /dev/null) ;;
    Darwin) GOROOTOWNER=$(stat -f "%Su" $GOROOT 2> /dev/null) ;;
esac

if [[ -z "$GOROOTOWNER" ]]
then
    echo "❌ Could't find owner of the \$GOROOT directory"
    exit 1
fi

if [[ "$USER" != "$GOROOTOWNER" ]]
then
    echo "🔥 Requires "$GOROOTOWNER" user access rights ..."

    SUDOCMD="sudo -u $GOROOTOWNER"
    $SUDOCMD echo -n ""
fi

GOARCH=$($GOBIN env GOARCH 2> /dev/null)

if [[ -z "$GOARCH" ]]
then
    echo "❌ Could't find \$GOARCH environment variable"
    exit 1
fi

GOOS=$($GOBIN env GOOS 2> /dev/null)

if [[ -z "$GOOS" ]]
then
    echo "❌ Could't find \$GOOS environment variable"
    exit 1
fi

GOTARBALL="https://go.dev/dl/$GOLATEST.$GOOS-$GOARCH.tar.gz"

$SUDOCMD rm -rf "$GOROOT"/*
$WGETCMD $GOTARBALL 2> /dev/null | $SUDOCMD $EXTRACTCMD $GOROOT 2> /dev/null

if [[ "$?" != "0" ]]
then
    $SUDOCMD rm -rf "$GOROOT"/*
    $CURLCMD $GOTARBALL 2> /dev/null | $SUDOCMD $EXTRACTCMD $GOROOT 2> /dev/null

    if [[ "$?" != "0" ]]
    then
        echo "❌ Couldn't download and unpack go with version $GOLATESTPRETTY"
        exit 1
    fi
fi

if [[ -n "$GOPATH" ]] && [[ "$GOPATH" == "$GOROOT"* ]]
then
    $SUDOCMD mkdir -p $GOPATH
fi

echo "👍 Go successfully upgraded from version $GOVERSIONPRETTY to version $GOLATESTPRETTY"
