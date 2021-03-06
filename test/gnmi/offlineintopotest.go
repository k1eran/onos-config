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
//

package gnmi

import (
	"context"
	"github.com/onosproject/onos-config/api/diags"
	"github.com/onosproject/onos-config/api/types/change"
	testutils "github.com/onosproject/onos-config/test/utils"
	"github.com/onosproject/onos-test/pkg/onit/env"
	"github.com/onosproject/onos-topo/api/device"
	"github.com/stretchr/testify/assert"
	"testing"
	"time"
)

const (
	offlineInTopoModPath          = "/system/clock/config/timezone-name"
	offlineInTopoModValue         = "Europe/Rome"
	offlineInTopoModDeviceName    = "offline-dev-1"
	offlineInTopoModDeviceVersion = "1.0.0"
	offlineInTopoModDeviceType    = "Devicesim"
)

// TestOfflineDeviceInTopo tests set/query of a single GNMI path to a single device that is in the config but offline
func (s *TestSuite) TestOfflineDeviceInTopo(t *testing.T) {
	deviceClient, deviceClientError := env.Topo().NewDeviceServiceClient()
	assert.NotNil(t, deviceClient)
	assert.Nil(t, deviceClientError)
	timeout := 10 * time.Second
	newDevice := &device.Device{
		ID:      offlineInTopoModDeviceName,
		Address: offlineInTopoModDeviceName + ":11161",
		Type:    offlineInTopoModDeviceType,
		Version: offlineInTopoModDeviceVersion,
		Timeout: &timeout,
		TLS: device.TlsConfig{
			Plain: true,
		},
	}
	addRequest := &device.AddRequest{Device: newDevice}
	addResponse, addResponseError := deviceClient.Add(context.Background(), addRequest)
	assert.NotNil(t, addResponse)
	assert.Nil(t, addResponseError)

	// Make a GNMI client to use for requests
	gnmiClient := getGNMIClientOrFail(t)

	// Set a value using gNMI client to the offline device
	devicePath := getDevicePathWithValue(offlineInTopoModDeviceName, offlineInTopoModPath, offlineInTopoModValue, StringVal)
	networkChangeID := setGNMIValueOrFail(t, gnmiClient, devicePath, noPaths, noExtensions)

	// Check that the value was set correctly
	checkGNMIValue(t, gnmiClient, devicePath, offlineInTopoModValue, 0, "Query after set returned the wrong value")

	// Check for pending state on the network change
	changeServiceClient, changeServiceClientErr := env.Config().NewChangeServiceClient()
	assert.Nil(t, changeServiceClientErr)
	assert.True(t, changeServiceClient != nil)
	listNetworkChangeRequest := &diags.ListNetworkChangeRequest{
		Subscribe:     true,
		ChangeID:      networkChangeID,
		WithoutReplay: false,
	}
	listNetworkChangesClient, listNetworkChangesClientErr := changeServiceClient.ListNetworkChanges(context.Background(), listNetworkChangeRequest)
	assert.Nil(t, listNetworkChangesClientErr)
	assert.True(t, listNetworkChangesClient != nil)
	networkChangeResponse, networkChangeResponseErr := listNetworkChangesClient.Recv()
	assert.Nil(t, networkChangeResponseErr)
	assert.True(t, networkChangeResponse != nil)
	assert.Equal(t, change.State_PENDING, networkChangeResponse.Change.Status.State)

	// Start the device simulator
	simulator := env.NewSimulator().SetName(offlineInTopoModDeviceName).SetAddDevice(false)
	simulatorEnv := simulator.AddOrDie()

	// Wait for config to connect to the device
	testutils.WaitForDeviceAvailable(t, offlineInTopoModDeviceName, 1*time.Minute)

	// Check that the network change has completed
	testutils.WaitForNetworkChangeComplete(t, networkChangeID, 10*time.Second)

	// Interrogate the device to check that the value was set properly
	deviceGnmiClient := getDeviceGNMIClientOrFail(t, simulatorEnv)
	checkDeviceValue(t, deviceGnmiClient, devicePath, offlineInTopoModValue)
}
