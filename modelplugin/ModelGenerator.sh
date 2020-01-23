#!/usr/bin/env bash

# See ../docs/modelplugin.md for how to use this file to generate a Model Plugin

if [ -z "$GOPATH" ] ; then
    echo 'No GOPATH environment variable specified'
    exit 1
fi

if [ $# -eq 0 ]
  then
    echo "No arguments supplied - expecting env file"
    exit 1
fi
source $1

if [ -z $TYPE ] ; then
    echo 'No TYPE given'
    exit 1
fi

if [ -z $VERSION ] ; then
    echo 'No VERSION given'
    exit 1
fi

if [ -z "$MODELDATA" ] ; then
    echo 'No MODELDATA given'
    exit 1
fi

TYPEVERSION=$TYPE-$VERSION
TYPELOWER=${TYPE,,}
VERSIONUS=${VERSION//[\.]/_}
TYPEVERSIONPKG=$TYPELOWER\_$VERSIONUS
TYPEMODULE=$TYPELOWER.so.$VERSION

mkdir -p $TYPEVERSION/$TYPEVERSIONPKG

createYangList() {
  readarray -d ';' array <<< "$MODELDATA"
  for yang in "${array[@]}"
  do
    YANGNAME=$(echo $yang | awk -F ',' '{print $1}')
    YANGORG=$(echo $yang | awk -F ',' '{print $2}')
    YANGVER=$(echo $yang | awk -F ',' '{print $3}')
    YANGFILEVER=$(echo $yang | awk -F ',' '{print $4}')
    if [ -z "$YANGFILEVER" ] ; then
      echo $YANGNAME@$YANGVER.yang" "
    else
      echo $YANGNAME@$YANGFILEVER.yang" "
    fi
  done
}

createModelDataJson() {
  readarray -d ';' array <<< "$MODELDATA"
  for yang in "${array[@]}"
  do
    YANGNAME=$(echo $yang | awk -F ',' '{print $1}')
    YANGORG=$(echo $yang | awk -F ',' '{print $2}')
    YANGVER=$(echo $yang | awk -F ',' '{print $3}')
    echo "    {Name:\""$YANGNAME"\",Organization:\""$YANGORG"\",Version:\""$YANGVER"\"},"
  done
}

YANGLIST="$( createYangList )"
echo "YANGLIST "$YANGLIST

MODELDATAJSON="$( createModelDataJson )"

go run $GOPATH/src/github.com/openconfig/ygot/generator/generator.go \
-path yang/$TYPEVERSION -output_file=$TYPEVERSION/$TYPEVERSIONPKG/generated.go -package_name=$TYPEVERSIONPKG \
-generate_fakeroot $YANGLIST

if [ $? -ne 0 ]; then
    echo 'ygot failed'
    exit 1
fi

# Update generated.go file

# sed in-place options require special handling on macOS.
sedi=(-i)
case "$(uname)" in
  Darwin*) sedi=(-i "")
esac

lf=$'\n'; sed "${sedi[@]}" \
-e "1s/^/\/\/ +build \!codeanalysis\\$lf\\$lf/" \
-e "1s/^/\/\/ Code generated by YGOT. DO NOT EDIT.\\$lf/" \
$TYPEVERSION/$TYPEVERSIONPKG/generated.go


# Generate model

cat > $TYPEVERSION/modelmain.go << EOF
// Copyright 2019-present Open Networking Foundation.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// +build modelplugin

// A plugin for the YGOT model of $TYPEVERSION.
package main

import (
	"fmt"
	"github.com/onosproject/onos-config/modelplugin/$TYPEVERSION/$TYPEVERSIONPKG"
	"github.com/openconfig/gnmi/proto/gnmi"
	"github.com/openconfig/goyang/pkg/yang"
	"github.com/openconfig/ygot/ygot"
)

type modelplugin string

const modeltype = "$TYPE"
const modelversion = "$VERSION"
const modulename = "$TYPEMODULE"

var modelData = []*gnmi.ModelData{
$MODELDATAJSON
}

func (m modelplugin) ModelData() (string, string, []*gnmi.ModelData, string) {
	return modeltype, modelversion, modelData, modulename
}

// UnmarshallConfigValues allows Device to implement the Unmarshaller interface
func (m modelplugin) UnmarshalConfigValues(jsonTree []byte) (*ygot.ValidatedGoStruct, error) {
	device := &$TYPEVERSIONPKG.Device{}
	vgs := ygot.ValidatedGoStruct(device)

	if err := $TYPEVERSIONPKG.Unmarshal([]byte(jsonTree), device); err != nil {
		return nil, err
	}

	return &vgs, nil
}

func (m modelplugin) Validate(ygotModel *ygot.ValidatedGoStruct, opts ...ygot.ValidationOption) error {
	deviceDeref := *ygotModel
	device, ok := deviceDeref.(*$TYPEVERSIONPKG.Device)
	if !ok {
		return fmt.Errorf("unable to convert model in to $TYPEVERSIONPKG")
	}
	return device.Validate()
}

func (m modelplugin) Schema() (map[string]*yang.Entry, error) {
	return $TYPEVERSIONPKG.UnzipSchema()
}

// GetStateMode returns an int - we do not use the enum because we do not want a
// direct dependency on onos-config code (for build optimization)
func (m modelplugin) GetStateMode() int {
	return 0 // modelregistry.GetStateNone
}

// ModelPlugin is the exported symbol that gives an entry point to this shared module
var ModelPlugin modelplugin
EOF
