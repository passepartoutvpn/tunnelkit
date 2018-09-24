#!/bin/sh
PWD=`dirname $0`
VERSION=`cat $PWD/VERSION`
BUILD=`git rev-list HEAD --count`
agvtool new-marketing-version $VERSION
agvtool new-version $BUILD
